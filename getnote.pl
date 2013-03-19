#!/usr/bin/perl
use lib '/Users/arenger/perl5/lib/perl5';
use strict;
use warnings;
use LWP::UserAgent 6.05;
use MIME::Base64;
use JSON;
use URI::Escape;

$| = 1;
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;
our $ua  = LWP::UserAgent->new;
our $url = 'https://simple-note.appspot.com';
our $login;
our $token = '';

sub setLoginInfo {
   our $login;
   my $authfile = shift;
   open( L , '<' , $authfile ) or die;
   $login = decode_json(join('',<L>));
   close( L );
   if ( !$login->{'email'} || !$login->{'password'} ) { die; }
}

sub setToken {
   our ($ua, $url, $token, $login);
   my $content = encode_base64(sprintf("email=%s&password=%s",
      $login->{'email'}, $login->{'password'}));
   my $response =  $ua->post($url . "/api/login", Content => $content);

   if ($response->content =~ /Invalid argument/) {
      die "Problem connecting to web server.\n".
          "Is Crypt:SSLeay installed?\n";
   }
   if ( !$response->is_success ) {
      die "Error logging into Simplenote server:\n".$response->content;
   }
   $token = $response->content;
}

sub printNoteObj {
   our ($ua, $url, $token, $login);
   my $key = shift;
   my $resp = $ua->get(sprintf(
      "%s/api2/data/%s?auth=%s&email=%s",
      $url, $key, $token, $login->{'email'}
   ));
   print $resp->content."\n";
}

#main
if (@ARGV != 2) {
   print "usage: $0 login.json noteKey\n";
   exit 1;
}
setLoginInfo($ARGV[0]);
setToken();
printNoteObj($ARGV[1]);
