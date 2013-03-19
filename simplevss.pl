#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use MIME::Base64;
use JSON;
use constant VSS_TODAY => 'VssToday';

$| = 1;
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;
our $ua  = LWP::UserAgent->new;
our $url = 'https://simple-note.appspot.com';
our $login;
our $token;

our %tags = (
   &VSS_TODAY  => 0,
   'Vss1Day'   => 86400,
   'Vss3Day'   => 259200,
   'Vss1Week'  => 604800,
   'Vss2Week'  => 1209600,
   'Vss1Month' => 2592000,
   'Vss90Day'  => 7776000
);

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
   $ua->agent('SimpleVss/2.0');
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

sub getNoteIndex {
   our ($ua, $url, $token, $login);
   my $index;
   my $mark = '';
   do {
      my $resp = $ua->get(sprintf(
         "%s/api2/index?length=30%s&auth=%s&email=%s",
         $url, $mark ? "&mark=$mark" : '', $token, $login->{'email'}
      ));
      my $struct = decode_json($resp->content);
      for my $meta (@{$struct->{'data'}}) {
         push @$index, $meta;
      }
      $mark = $struct->{'mark'};
   } while ( $mark );
   return $index;
}

sub tagNotes() {
   our ($ua, $url, $token, $login, %tags);
   my $index = getNoteIndex();
   my $now = time();
   for my $meta (@$index) {
      #printf("checking %s\n",$meta->{'key'});
      my @tagSubset = ();
      my $alreadyToday = 0;
      for my $tag (@{$meta->{'tags'}}) {
         if (exists($tags{$tag})) {
            push @tagSubset, $tag;
            if ($tag eq &VSS_TODAY) {
               $alreadyToday = 1;
               last;
            }
         }
      }
      next if $alreadyToday;
      for my $tag (@tagSubset) {
         my $then = $meta->{'modifydate'};
         $then -= ($then % 86400);
         $then += $tags{$tag};
         if ( $now > $then ) {
            $ua->post(
               sprintf( "%s/api2/data/%s?auth=%s&email=%s",
                  $url, $meta->{'key'}, $token, $login->{'email'}),
               # not yet supporting the preservation of unrelated tags -
               Content => sprintf('{"modifydate":"%s","tags":["%s","%s"]}',
                  $now, $tag, &VSS_TODAY)
            );
            printf("modified: %s\n",$meta->{'key'});
         }
      }
   }
}

#main
if (@ARGV != 1) {
   print "usage: $0 login.json\n";
   exit 1;
}
setLoginInfo($ARGV[0]);
setToken();
tagNotes();
