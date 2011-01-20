#!/gsc/bin/perl

use strict;
use warnings;
use Data::Dumper;
use GSCApp;
use DBI;
use File::Basename;
use Date::Manip;

App::DB->db_access_level('rw');

App->init;

my $path = Path::Class::Dir->new('/gsc/var/log/confirm_scheduled_pse/lsf_stats');

my $max = 100;

my $debug = 0;

my @errors;
my $job_id;  # = $ENV{'LSB_JOBID'};
my $yesterday = UnixDate(DateCalc("today","- 120hours"), "%Y-%m-%d %H:%M:%S" );

if (! scalar @ARGV) {
  print "Usage: " . basename $0 . " <list of build ids>\n";
  exit 1;
}

my $jobid = join(',',@ARGV);

#my $sql = "select * from grid_jobs_finished where end_time >= '$yesterday' and projectname like 'build%'";
my $sql = "select * from grid_jobs_finished where jobid in \($jobid\)";

&error_out(App::Time->now . " " .$sql) if $debug;;

my $dbh = App::DB::Login->get(server => 'rtm.gsc.wustl.edu')->connect;

my $sth =$dbh->prepare($sql);
$sth->execute;

#this is necessary for mysql => oracle conversion
my $foo_date = '0001-01-01 00:00:01';
my @builds;
my $i=0;

OUTER: while(my $ref = $sth->fetchrow_hashref()){
    $i++;

    unless($ref and %$ref){
        print "no data\n";
        exit;
    }

    for(keys %$ref){
#make oracle happy
        if((/time/i and $ref->{$_} eq '0000-00-00 00:00:00') or /last_updated/){
            $ref->{$_}=$foo_date;
        }

        my $nkey = lc $_;
        $ref->{$nkey}= delete $ref->{$_};
    }

    if(exists $ref->{user}){
        $ref->{bjob_user} = delete $ref->{user};
    }

    # Backfilling requires build$ID within outfile string
    #my $projectname = $ref->{projectname};
    my $outfile = $ref->{outfile};
    my $command = $ref->{command};
    my $job_id = $ref->{jobid};

    my $build_id ;
    #if ($projectname =~/^build(\d+)/) {
    if ($outfile =~/\/build(\d+)\//) {
        $build_id = $1;
        unless($build_id){
            push @errors, $job_id;
            &error_out("couldn't find build-id in: $outfile for $command");
            next;
        }
    } else {
        &error_out("can't extract build ID from 'outfile' field: $outfile for $command. skip " . $job_id);
        die;
    }

    my @build_bj = GSC::BuildIDGridJobFinished->get(build_id => $build_id);
    foreach my $bj (@build_bj) {
        my $bjob = GSC::GridJobFinished->get(bjob_id => $bj->bjob_id);
        if ($bjob and $bjob->jobid == $ref->{jobid}) {
            $i--;
            next OUTER;
        }
    }

    my $bjob = GSC::GridJobFinished->get(jobid => $ref->{jobid} , submit_time => $ref->{submit_time}, indexid  => $ref->{indexid});
    if(!$bjob){

        # Enter a job id in Oracle's mirror of RTM table grid_job_finished
        #
        $bjob = GSC::GridJobFinished->create(%$ref);
        unless($bjob){
            #print Dumper $ref;
            &error_out("couldn't create bjob: " . $ref->{jobid});
            die;
        }
        &error_out(App::Time->now . " creating bjob " . $bjob->id . " build_id: " . $build_id ) if $debug;;

    }
    print "CREATED jobid: " . $ref->{jobid} . "\n";

    my $build_bj = GSC::BuildIDGridJobFinished->create(bjob_id => $bjob->id, build_id => $build_id);

    unless($build_bj){
        &error_out( "couldn't create bjob_build for build_id: $build_id bjob_id: ". $bjob->id . "\n");
        die ;
    }

    push @builds, $build_id;

    if(scalar(@builds) > $max){
        App::DB->sync_database;
        App::DB->commit; 
        $max = scalar(@builds) + 200;
    }
}

$dbh->disconnect();

# FIXME: turn this back on when we're writing to DB.
App::DB->sync_database;
App::DB->commit;

# Below here is QC for sabbott.
#if(@builds and scalar(@builds) > 200){
#    my $m = GSC::Report::Model::PSE->new(entity_data => [GSC::PSE->get(\@builds)]);
#    my $v = GSC::Report::View::PSE->new(report_type => 'lsf', model => $m, email => 'sabbott' );
#    $v->report;
#}
#
#if (@errors) {
#    my $string = join("\n", @errors) ;
#    my $to = "sabbott";
#    my $subject = "unparsable grid_jobs_finished projectname entries\n";
#            my $content = <<HERE;
#To: $to
#From: CronMcGee <lims\@watson.wustl.edu>
#Subject: $subject
#Content-Type: text/html; charset="us-ascii"
#
#$string
#HERE
#        open F, "|sendmail $to" or die ;
#        print F $content;
#        close F;
#
#}

# FIXME: update logging
sub error_out {
    my $msg = shift;
    print "$msg\n";
    #my $file = $path->file('errors.log');
    #my $fh = $file->open('>>') or die;
    #$fh->say($msg);
    #$fh->close;
    return;
}
