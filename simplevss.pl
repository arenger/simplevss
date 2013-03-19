#!/usr/bin/perl
use lib '/Users/arenger/perl5/lib/perl5';
use strict;
use warnings;
use LWP::UserAgent 6.05;
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
   VSS_TODAY   => 0,
   'Vss1Day'   => 86400,
   'Vss3Day'   => 259200,
   'Vss1Week'  => 604800,
   'Vss2Week'  => 1209600,
   'Vss1Month' => 2592000,
   'Vss90Day'  => 7776000
);

# maybe in future:
# $index will contain the "data" portion of the response from an index
# request to the server.  on startup, simplevss loads this from a file
# and then gets any needed updates to it from the server.  this structure
# is saved to index.json before the program ends.  it is an array of hashes.
# our $index;

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
   my $now = time();
   my $index = getNoteIndex();
   for my $meta (@$index) {
      #printf("checking %s\n",$meta->{'key'});
      for my $tag (@{$meta->{'tags'}}) {
         next if !$tags{$tag};
         #printf("  has tag: $tag\n");
         if ( $now > ($meta->{'modifydate'} + $tags{$tag}) ) {
            my $resp = $ua->post(
               sprintf( "%s/api2/data/%s?auth=%s&email=%s",
                  $url, $meta->{'key'}, $token, $login->{'email'}),
               # not yet supporting the preservation of unrelated tags,
               # and/or multiple frequencies if that would even make sense -
               Content => sprintf('{"modifydate":"%s","tags":["%s","%s"]}',
                  $now, $tag, VSS_TODAY)
            );
            #print "modifed: ".$resp->content."\n";
            printf("modified: %s\n",$meta->{'key'});
         }
      }
   }
}

#main
print "begin main\n";
if (@ARGV != 1) {
   print "usage: $0 login.json\n";
   exit 1;
}
setLoginInfo($ARGV[0]);
setToken();
tagNotes();
print "end main\n";
