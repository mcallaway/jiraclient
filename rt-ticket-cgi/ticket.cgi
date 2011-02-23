#!/usr/bin/perl

use strict;
use warnings;
use Error qw(:try);
use CGI;
use RT::Client::REST::Ticket;
use Data::Dumper;

# Configurables
my $rturl = 'https://10.0.24.77';
my $queue = 'test';

# Subroutines
sub mydie {
  my $message = shift;
  print "Content-Type: text/html\n\n";
  print <<EOF;
<html>
<body>
<p>There was an error submitting data to RT: $rturl</p>
<p>$message</p>
</body>
</html>
EOF
  exit 1;
}

sub respond {
  my $content = shift;
  my $response = HTTP::Response->new(200);
  $response->header("Content-Type" => "text/html");
  $response->content($content);
  print $response->headers_as_string;
  print "\n\n";
  print $response->decoded_content;
}

sub RT_createTicket {
  my $query = shift;

  my $requestor = $query->param('username');
  my $size = $query->param('size');
  $size = $query->param('othersize') if ($size eq 'other');
  my $backup = $query->param('backup');
  my $type = $query->param('type');
  my $group= $query->param('group');
  my $subject = "Storage Request: $size for $requestor";
  my $text = $query->param('description');

  my $content = <<EOT;
Disk Storage Request:
Requestor: $requestor
Size: $size
Backup: $backup
Type: $type
Group: $group

$text
EOT

  # Use the _cookie parameter when we figure that out
  my $rt = RT::Client::REST->new(
    server => $rturl,
  );

  try {
    $rt->login( username => $requestor, password => $query->param('password') );
  } catch Error with {
    mydie "Problem logging into RT: " . shift->as_string();
  };

  my $ticket;
  try {
    $ticket = RT::Client::REST::Ticket->new(
      rt => $rt,
      queue => $queue,
      subject => $subject,
      )->store(text => $content);
  } catch Error with {
    mydie "Problem submitting to RT: " . shift->as_string();
  };

  respond( result_page($ticket,$content) );
}

sub result_page {

  my $ticket = shift;
  my $content = shift;
  my $id = $ticket->id;
  my $turl = $rturl . "/Ticket/Display.html?id=" . $ticket->id;
  my $time = 3;

  $content =~ s/\n/<br>/g;

  my $result = <<EOT;
<html>
<head>
<title>Successfully created ticket $id</title>
<!--
<meta http-equiv="refresh" content="$time; URL=$turl">
-->
</head>
<body>
<h3>Submission Result</h3>
<p>You created ticket: <a href=$turl>$id</a></p>
<p>$content</p>
</body>
</html>
EOT
  return $result;
}

# Main
my $query = new CGI(\*STDIN);
my $params = $query->Vars;
RT_createTicket($query);

