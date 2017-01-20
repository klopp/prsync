#!/usr/bin/perl

# ------------------------------------------------------------------------------
use strict;
use warnings;
use open qw/:utf8 :std/;
use Getopt::Long;
use File::Temp qw/tempfile/;
use File::Basename qw/basename fileparse/;
use POSIX qw/strftime :sys_wait_h/;
use Number::Format qw(:subs);
use DDP;

# ------------------------------------------------------------------------------
my $VERSION   = '1.3    ';
my $SUDO      = '/usr/bin/sudo';
my $BASENAME  = basename($0);
my $SUFFIX    = $BASENAME =~ /./ ? ( fileparse( $0, qr/\.[^.]*/ ) ) : $BASENAME;
my $opt_p     = 4;
my $opt_rsync = '/usr/bin/rsync';
my $opt_find  = '/usr/bin/find';
my $opt_sort  = '/usr/bin/sort';
my $opt_ropt  = '--delete -a -q';
my $opt_size  = '10M';
my $opt_tmp   = '/tmp';
my $opt_sudo;
my $opt_v;
my $opt_d;
my $opt_src;
my $opt_dst;
my $opt_nl;

# ------------------------------------------------------------------------------
usage()
    unless (
    @ARGV
    && GetOptions(
        'v'       => \$opt_v,
        'd'       => \$opt_d,
        'p=i'     => \$opt_p,
        'src=s'   => \$opt_src,
        'dst=s'   => \$opt_dst,
        'tmp=s'   => \$opt_tmp,
        'size=s'  => \$opt_size,
        'sudo:s'  => \$opt_sudo,
        'rsyns=s' => \$opt_rsync,
        'nl'      => \$opt_nl,      # no real launch rsync
    )
    );

usage('Invalid "p" option') if $opt_p < 1;
usage('No "src" option') unless $opt_src;
usage('No "dst" option') unless $opt_dst;
$opt_sudo = $SUDO if defined $opt_sudo && !$opt_sudo;
usage("Can not find \"sudo\" executable ($opt_sudo)")
    if $opt_sudo && !-x $opt_sudo;
usage("Can not find \"rsync\" executable ($opt_rsync)") unless -x $opt_rsync;
usage("Can not find \"find\" executable ($opt_find)")   unless -x $opt_find;
usage("Can not find \"sort\" executable ($opt_sort)")   unless -x $opt_sort;
mkdir $opt_dst;
usage("No access to destination directory \"$opt_dst\"")
    unless -d $opt_dst && -w $opt_dst;
usage("No access to temporary directory \"$opt_tmp\"")
    unless -d $opt_tmp && -w $opt_tmp;

# ------------------------------------------------------------------------------
$opt_ropt = join ' ', @ARGV if @ARGV;
$opt_src =~ s/\/*$//g;
$opt_dst =~ s/\/*$//g;
$opt_src =~ /^.+(\/[^\/]+$)/ and my $transfer_root = $1;

# ------------------------------------------------------------------------------
my @tempfiles;
my @parts;
my %sums = map { $_ => 0 } ( 0 .. $opt_p - 1 );
my %children;
my ( $gexh, $gexn );

pv( 'Sync "%s" => "%s"...', $opt_src, $opt_dst );
pv('Collect files...');

my $find = ( $opt_sudo ? "$opt_sudo " : '' ) . $opt_find;
my $sort = ( $opt_sudo ? "$opt_sudo " : '' ) . $opt_sort;
my $cmd = "$find \"$opt_src\" -type f -size +$opt_size -printf \"\%s \%p\\n\"| $sort -gr |";
pd( '%s', $cmd );
if ( open my $dh, $cmd ) {

    eval { ( $gexh, $gexn ) = tempfile( 'exclude-XXXX', SUFFIX => ".$SUFFIX", DIR => $opt_tmp ); };

    if ($@) {
        close $dh;
        print "ERROR: can not create exclusion file in \"$opt_tmp\": $@";
        exit 2;
    }

    my $line = <$dh>;
    while ($line) {

        for ( my $i = 0; $i <= ( $opt_p > 1 ? $opt_p - 2 : 0 ) && $line; ++$i ) {

            my ( $size, $name ) = split /\s+/, $line;
            next unless $name;
            $name =~ s/$opt_src\///;
            print $gexh "$transfer_root/$name\n";
            if ( $sums{$i} < $sums{ $i + 1 } ) {
                $sums{$i} += $size;
                push @{ $parts[$i] }, "/$name";
            }
            else {
                $sums{ $i + 1 } += $size;
                push @{ $parts[ $i + 1 ] }, "/$name";
            }
            $line = <$dh>;
        }
    }
    close $gexh;
    close $dh;
}
else {
    print "ERROR: can not execute '$cmd': $!\n";
    exit 3;
}

pv('Processes creating...');
local $SIG{CHLD} = sub {
    while ( ( my $pid = waitpid( -1, WNOHANG ) ) > 0 ) {
        if ( exists $children{$pid} ) {
            pv( 'Child [%d] finished!', $pid );
            delete $children{$pid};
        }
    }
};

for ( sort { $sums{$b} <=> $sums{$a} } keys %sums ) {

    next unless @{ $parts[$_] };

    my ( $th, $tn );
    eval { ( $th, $tn ) = tempfile( 'include-XXXX', SUFFIX => ".$SUFFIX", DIR => $opt_tmp, ); };

    if ($@) {
        unlink $gexn, @tempfiles;
        kill 'TERM', keys %children;
        print "ERROR: can not create list file in \"$opt_tmp\": $@";
        exit 2;
    }

    push @tempfiles, $tn;
    print $th join "\n", @{ $parts[$_] };
    close $th;

    my $pid = fork();
    die "$!\n" unless defined $pid;
    if ( !$pid ) {
        my $rsync = ( $opt_sudo ? "$opt_sudo " : '' )
            . "$opt_rsync $opt_ropt --files-from=\"$tn\" \"$opt_src\" \"$opt_dst$transfer_root\"";
        pv( '[%d] Sync part (%s)', $$, format_bytes( $sums{$_} ) );
        pd( '[%d] Launch %s', $$, $rsync );
        if ($opt_nl) {
            sleep 4;
            exit 0;
        }
        else {
            exec $rsync;
        }
    }
    else {
        $children{$pid} = undef;
    }
}

my $rsync = ( $opt_sudo ? "$opt_sudo " : '' )
    . "$opt_rsync $opt_ropt --exclude-from=\"$gexn\" \"$opt_src\" \"$opt_dst\"";
pv('Sync root');
pd( '[*] Launch %s', $rsync );
system $rsync unless $opt_nl;

pv('Root ready, wait for children...');
sleep 1 while ( scalar keys %children );
pv('Done');

#unlink $gexn, @tempfiles;

# ------------------------------------------------------------------------------
sub _pp
{
    my $opt = shift;
    return unless $opt;
    my $fmt = shift;
    print strftime '[%F %H:%M:%S] ', localtime;
    return printf( "$fmt\n", @_ );
}

# ------------------------------------------------------------------------------
sub pv
{
    return _pp( $opt_v, @_ );
}

# ------------------------------------------------------------------------------
sub pd
{
    return _pp( $opt_d, @_ );
}

# ------------------------------------------------------------------------------
sub usage
{
    my ($msg) = @_;
    print "\n$msg!\n" if $msg;
    my $u = <<'EOU';

Milti-threaded rsync wrapper, version %s. (C) Vsevolod Lutovinov <klopp@yandex.ru>, 2017.
Usage: %s [options]
Valid options, * - required:
    -src   DIR   *  source directory
    -dst   DIR   *  destination directory
    -tmp   DIR      temporary directory, default: '%s'
    -rsync PATH     'rsync' executable, default: '%s'
    -find  PATH     'find' executable, default: '%s'
    -sort  PATH     'sort' executable, default: '%s'
    -sudo  [PATH]   use sudo ['sudo' executable], defaults: NO, executable: '%s'
    -size  SIZE     file size to put it in papallel process, default: '%s' 
                    about size's format see man find, command line key '-size' 
    -p     N        max processes, >0, default: '%d'
    -v              increase verbosity
    -d              print debug information
    --     OPT      rsync options, default: '%s'

EOU
    printf $u, $VERSION, $BASENAME, $opt_tmp, $opt_rsync, $opt_find, $opt_sort, $SUDO,
        $opt_size, $opt_p, $opt_ropt;
    exit 1;
}

# ------------------------------------------------------------------------------
