#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use MIME::Base64;
use JSON qw( decode_json );
use POSIX qw/strftime/;
use Time::Local;
use URI::Escape;

$| = 1;
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;
our $ua  = LWP::UserAgent->new;
our $url = 'https://simple-note.appspot.com/api/';
our $tok = '';
our %dat = ();
our %login = ();
our %gtime = (    # a - daily
   'b', 259200,   # b - review in 3 days
   'c', 604800,   # c - review in 7 days
   'd', 1209600,  # d - review in 14 days
   'e', 2592000,  # e - review in 30 days
   'f', 5184000,  # f - review in 60 days
   'g', 10368000  # g - review in 120 days
);

sub trim {
   $_ = shift;
   s/^\s+//g;
   s/\s+$//g;
   return $_;
}

sub setLoginInfo {
   our( %login );
   open( L , '<' , 'login' ) or die;
   $login{'email'}    = trim( scalar(<L>) );
   $login{'password'} = trim( scalar(<L>) );
   close( L );
   if ( !$login{'email'} || !$login{'password'} ) { die; }
}

sub setToken {
   our ($ua, $url, $tok, %login);
   my $content = encode_base64(sprintf("email=%s&password=%s",
      $login{'email'}, $login{'password'}));
   my $response =  $ua->post($url . "login", Content => $content);

   if ($response->content =~ /Invalid argument/) {
      die "Problem connecting to web server.\n".
          "Is Crypt:SSLeay installed?\n";
   }
   if ( !$response->is_success ) {
      die "Error logging into Simplenote server:\n".$response->content;
   }
   $tok = $response->content;
}

# TODO use API v2 one day
sub getIndex {
   our ($ua, $url, $tok);
   #open(J,'<','../index.json.txt') or die;
   #my $json = join('',<J>);
   #close(J);
   #return $json;
   my $response = $ua->get( sprintf("%sindex?auth=%s&email=%s",
      $url,$tok,$login{'email'}));
   die if !$response->is_success;
   return $response->content;
}

sub ts2str {
   return strftime( '%Y-%m-%d %H:%M:%S' , gmtime(shift) );
}

sub str2ts {
   #expecting format like this: 2012-12-04 03:52:11
   my @a = split(/[- :]/,shift);
   return timegm(
      int($a[5]), $a[4], $a[3], $a[2], $a[1] - 1, $a[0] - 1900 );
}

# TODO move to SQLite at some point...
#format: id,modified,downloaded,vssGroup
sub loadDat {
   our( %dat );
   my $r = open( D , '<' , 'dat.txt' );
   if ( !$r ) { return; }
   while ( <D> ) {
      chop;
      @_ = split /,/;
      my $k = $_[0];
      $dat{$k}{'modified'} = $_[1];
      $dat{$k}{'downloaded'} = $_[2];
      $dat{$k}{'vssGroup'} = $_[3];
   }
   close( D );
}

# TODO move to SQLite at some point...
sub saveDat {
   our( %dat );
   open( D , '>' , 'dat.txt' ) or die;
   for my $k ( keys( %dat ) ) {
      printf( D "%s,%d,%d,%s\n", $k,
         $dat{$k}{'modified'},
         $dat{$k}{'downloaded'},
         $dat{$k}{'vssGroup'}
      );
   }
   close( D );
}

sub getNote {
   our ($ua, $url, $tok, %login);
   my $key = shift;
   my $response = $ua->get(
      sprintf("%snote?key=%s&auth=%s&email=%s&encode=base64",
      $url,$key,$tok,$login{'email'}));
   die if !$response->is_success;
   return decode_base64($response->content);
}

sub updateNoteLocal {
   our( %dat );
   my ($k,$modified) = @_;
   my $debug = 0;
   my $txt = '';
   if ( !$debug ) {
      $txt = getNote( $k );
      open( N , '>' , "notes/$k") or die;
      print N $txt;
      close( N );
      chmod 0600, "notes/$k";
   } else {
      open( N , '<' , "notes/$k") or die;
      $txt = join( '' , <N> );
      close( N );
   }
   #update %dat -
   $dat{$k}{'modified'} = $modified;
   $dat{$k}{'downloaded'} = time();
   my $group = 0;
   if ( $txt =~ /<vss-(.)\/>/ ) {
      $group = $1;
   }
   $dat{$k}{'vssGroup'} = $group;
}

sub getLatest {
   our( %dat );
   my $ret = decode_json( getIndex() );
   for my $r ( @$ret ) {
      my $k = $r->{'key'};
      my $mts = str2ts($r->{'modify'});
      if ( !$r->{'deleted'} ) {
         if ( $dat{$k} ) {
            $dat{$k}{'modified'} = $mts;
            if ( $mts > $dat{$k}{'downloaded'} ) {
               print "Refresh: $k\n";
               updateNoteLocal( $k , $mts );
            }
         } else {
            #get note and save to notes -
            print "Download: $k\n";
            updateNoteLocal( $k , $mts );
         }
      } else {
         delete $dat{ $k };
      }
   }
}

sub moveVss {
   our( $ua, $url, $tok, %login );
   our( %dat, %gtime );
   my $now = time();
   for my $k ( keys( %dat ) ) {
      my $g = $dat{$k}{'vssGroup'};
      if ( $gtime{$g} ) {
         print "Checking note: $k\n";
         my $modified = $dat{$k}{'modified'};
         $modified -= ( $modified % 86400 );
         if ( ( $now - $modified ) > $gtime{$g} ) {
            printf( "Moving.  (%d > %d)\n",
               ( $now - $modified ), $gtime{$g} );

            # load local copy -
            open( N , '<' , "notes/$k" );
            my $n = join( '' , <N> );
            close( N );
            
            # move to group a
            $n =~ s/<vss-$g\/>/<vss-a\/>/g;
            # rewrite to disk
            open( N , '>' , "notes/$k" );
            print N $n;
            close( N );

            # update %dat
            $dat{$k}{'vssGroup'} = 'a';
            $dat{$k}{'modified'} = $now;

            # tell the simplenote server
            my $response = $ua->post(
               sprintf("%snote?key=%s&auth=%s&email=%s&modified=%s",
               $url,$k,$tok,$login{'email'},uri_escape(ts2str($now)) ),
               Content => encode_base64( $n ) );
            print $response->content."\n";
         }
      }
   }
}

#main
print "begin main\n";
if ( !$ENV{'SIMPLEVSS_HOME'} ) {
   print "SIMPLEVSS_HOME must be set\n";
   exit 1;
}
chdir( $ENV{'SIMPLEVSS_HOME'}."/work" ) or die;
if ( mkdir( 'notes' ) ) { print "Created notes directory\n"; }

setLoginInfo();
setToken();
loadDat();
getLatest();

moveVss();

saveDat();
print "end main\n";
