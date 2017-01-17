#!/usr/bin/perl

# ------------------------------------------------------------------------------
use strict;
use warnings;
use open qw/:utf8 :std/;
use Getopt::Long;
use File::Basename qw/basename fileparse/;
use File::Temp qw/tempfile/;
use POSIX qw/strftime/;
use AnyEvent::ForkManager;

# ------------------------------------------------------------------------------
my $VERSION   = '1.0';
my $SUDO      = '/usr/bin/sudo';
my $opt_p     = 16;
my $opt_rsync = '/usr/bin/rsync';
my $opt_ropt  = '--delete -a --info=none,name1,copy1';
my $opt_tmp   = '/tmp';
my $opt_sudo  = undef;
my $opt_src;
my $opt_dst;
my $opt_v;
my $opt_d;

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
        'rsyns=s' => \$opt_rsync,
        'sudo:s'  => \$opt_sudo,
    )
    );

usage('Invalid "p" option') if $opt_p < 2;
usage('No "src" option') unless $opt_src;
usage('No "dst" option') unless $opt_dst;
$opt_sudo = $SUDO if defined $opt_sudo && !$opt_sudo;
usage("Can not find \"sudo\" executable ($opt_sudo)")
    if $opt_sudo && !-x $opt_sudo;
usage("Can not find \"rsync\" executable ($opt_rsync)") unless -x $opt_rsync;
usage("No access to temporary directory \"$opt_tmp\"")
    unless -d $opt_tmp && -w $opt_tmp;
mkdir $opt_dst;
usage("No access to destination directory \"$opt_dst\"") unless -d $opt_dst;

# ------------------------------------------------------------------------------
$opt_ropt = join ' ', @ARGV if @ARGV;
$opt_src =~ s/\/*$//g;
$opt_dst =~ s/\/*$//g;
my @entries;
my %excludes;
my $spider;

pv( 'Sync "%s" => "%s"...', $opt_src, $opt_dst );

#step 1: create directories:
pv('Creating directory tree...');
my $rsync = '';
$rsync = "$opt_sudo " if $opt_sudo;
$rsync .= "$opt_rsync -a -f\"+ */\" -f\"- *\" --numeric-ids \"$opt_src\" \"$opt_dst";
$rsync =~ s/\/[^\/]*$//;
$rsync .= '"';
pd($rsync);
system $rsync;

$spider = AnyEvent::ForkManager->new(
    max_workers => $opt_p,
    on_start    => sub {
        my ( $pm, $pid, $dir ) = @_;
        pd( '[%d] start sync "%s"', $pid, $dir );
    },

    on_finish => sub {
        my ( $pm, $pid, $status, $dir ) = @_;
        pd( '[%d] "%s" sync status: %s', $pid, $dir, $status );
    }
);

# step 2, sync nested directories:
pv('Collect files...');
collect_entries( $opt_src, \@entries, 0, 0 );
@entries = sort { scalar split( '/', $b ) <=> scalar split( '/', $a ) } @entries;
pv('Sync directory tree...');
sync_entries( \@entries );

#step 3, scan files in top-level directory:
pv('Collect root entries...');
$#entries = -1;
collect_entries( $opt_src, \@entries, 0, 1 );
pv('Sync root entries...');
sync_entries( \@entries, 1 );

# ------------------------------------------------------------------------------
sub sync_entries
{
    my ( $entries, $is_file ) = @_;
    foreach my $dir ( @{$entries} ) {
        $spider->start(
            cb => sub {
                my ( $pm, $dir ) = @_;
                sync_entry( $$, $dir, $is_file );
            },
            args => [$dir]
        );
    }

    my $condvar = AnyEvent->condvar;
    $spider->wait_all_children(
        cb => sub {
            my ($pm) = @_;
            pv('Done.');
            $condvar->send;
        }
    );
    $condvar->recv;
}

# ------------------------------------------------------------------------------
sub sync_entry
{
    my ( $id, $source, $is_file, $rsync_opt ) = @_;

    $rsync_opt ||= $opt_ropt;
    my $target = $source;
    $target =~ s/^$opt_src//;
    $target = "$opt_dst$target";

    $source =~ s/\/*$//g;
    $target =~ s/\/*$//g;

    unless ($is_file) {
        $source .= '/';
        $target .= '/';
    }

    my $rsync = '';
    $rsync = "$opt_sudo " if $opt_sudo;
    $rsync .= "$opt_rsync ";
    my ( $th, $tn );

    if ( !$is_file && scalar keys %excludes ) {
        eval {
            ( $th, $tn ) = tempfile(
                'XXXXXXXX',
                SUFFIX => '.' . ( fileparse( $0, qr/\.[^.]*/ ) )[0] || '$$$',
                DIR => $opt_tmp,
            );
        };

        if ($@) {
            print "ERROR: can not create temp file in \"$opt_tmp\":\n$@";
            return;
        }
        print $th join( "\n", map { $_ eq $source ? '' : "$_/.*\n$_*" } keys %excludes );
        close $th;
        $rsync .= '--exclude-from="' . $tn . '" ';
    }

    $rsync .= "$rsync_opt \"$source\" \"$target\"";
    pd( '[%d] %s', $id, $rsync );
    system $rsync;
    unlink $tn if $tn;
}

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
sub collect_entries
{
    my ( $dir, $entries, $lvl, $files_only ) = @_;

    $lvl ||= 0;
    if ($opt_sudo) {
        my $find_args = $files_only ? '-maxdepth 1 -type f' : '-type d';
        my $find = "$opt_sudo find \"$dir\" $find_args |";
        if ( open my $dh, '<', $find ) {
            while ( defined( my $line = <$dh> ) ) {
                chomp $line;
                push @{$entries}, $line;
            }
            close $dh;
        }
        else {
            print "ERROR: can not open \"$find\":\n\t$!\n";
            exit 2;
        }
    }
    else {
        if ( opendir my $dh, $dir ) {
            my @de = readdir $dh;
            closedir $dh;
            for (@de) {
                next if $_ eq '.' || $_ eq '..';
                if ($files_only) {
                    push @{$entries}, "$dir/$_" if -f "$dir/$_";
                }
                else {
                    next unless -d "$dir/$_";
                    push @{$entries}, "$dir/$_";
                    collect_entries( "$dir/$_", $entries, $lvl + 1, $files_only );
                }
            }
        }
        elsif ( !$lvl ) {

            # show error for top level only
            print "ERROR: can not open directory \"$dir\": $!\n";
            exit 2;
        }
        else {
            print "Skip directory \"$dir\": $!\n" if $opt_v;
            $excludes{$dir} = undef;
        }
    }

    return $entries;
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
    -src   DIR   * source directory
    -dst   DIR   * destination directory
    -tmp   DIR     temporary directory, default: '%s'
    -rsync PATH    rsync executable, default: '%s'
    -sudo  [PATH]  use sudo [executable], default: NO, executable: '%s'
    -p     N       max processes, > 1, default: '%d'
    -v             increase verbosity
    -d             print debug information
    --     OPT     rsync options, default: '%s'

EOU
    printf $u, $VERSION, basename($0), $opt_tmp, $opt_rsync, $SUDO, $opt_p, $opt_ropt;
    exit 1;
}

# ------------------------------------------------------------------------------