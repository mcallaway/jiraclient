#!/gsc/bin/perl

use Mail::Sendmail;

open(LOG,">>/var/log/password_reminder.log");

my %users;
my $datesec = `date \+\%s`;
my $currentday = int ( $datesec / 86400 );
#my $warningtime = $currentday - 351;

foreach $uid ( `ldapsearch -x | grep uid: | awk '{ print \$2 }'` ) {
	chomp $uid;
	#my $shadow = `ldapsearch -x '(uid\=$uid)' | grep shadowLastChange: | awk '{ print \$2 }'`;
	#chomp $shadow;

	my $command = `ldapsearch -x '(uid\=$uid)' shadowLastChange mail`;
	$command =~ /shadowLastChange: (\d+)/;
	my $shadow = $1;

	$command =~ /mail: (.*)/;
	my $email = $1;

	$users{$uid}{shadow} = $shadow;
	$users{$uid}{email} = $email;
}

foreach $uid ( keys %users ) {
	# if their shadowLastChange is older than 351 days, give a warning

	my $expireday = ( 365 - ( $currentday - $users{$uid}{shadow}) );
	my $timestamp = `date +%D`;
	chomp $timestamp;

	# skip and log if time left < 0 (may be inactive)
	if( $expireday < 0 ) {
		# dont log zero'd value since it may be new user
		if( $users{$uid}{shadow} != 0 ) {
			print LOG "$timestamp: $uid password expired - value: $users{$uid}{shadow}\n";
		}
		next;
	} elsif ( $expireday < 15 ) {
		#send email to remind user
		my $name = (getpwnam($uid))[6];
		#print "$name: your email will expire in $expireday days\n";
		#print "sending to email address $users{$uid}{email}\n";
		#next;
		print LOG "$timestamp: sending reminder to $uid\n";
		sendmail
		(
		  From => 'systems@genome.wustl.edu',
		  To => "$users{$uid}{email}",
		  Subject => "Your Genome Center unix/mail password will expire in $expireday days",
		  Message => "Hello $name,\n\nThe Genome Center currently has a policy that passwords must be changed\nevery year.  Your unix\/email password is about to expire and needs to\nbe changed to insure you are not locked out of the system.\n\nSome \'Phishing\' scams will send mails like this and give you a link\nto follow that will ask for your username and password.  Do not respond\nto those\!  To differentiate this mail, we ask you to manually go to the\nGenome Center\'s wiki \'Main Page\' on gscweb, click on \'How To\' and then\nclick on \'Change your password\'.  At that point you will be asked for\nyour information but you will have arrived at it yourself rather than\nfollowing a link.\n\nYou will continue to receive reminder emails until the password is\nupdated or expires.  If you have any questions\/problems please open\na ticket in the RT system.\n\nThank you,\nThe Information Systems Group\nsystems\@genome.wustl.edu"
		) or warn ("sendmail failed: $Mail::Sendmail::error");
		
	}
}

