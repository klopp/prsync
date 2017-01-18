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
use Encode qw/decode_utf8/;
use DDP;

# ------------------------------------------------------------------------------
my $VERSION   = '1.1';
my $SUDO      = '/usr/bin/sudo';
my $opt_p     = 8;
my $opt_rsync = '/usr/bin/rsync';
my $opt_ropt  = '--delete -a --info=none,name1,copy1';
my $opt_tmp   = '/tmp';
my $opt_size  = '10M';
my $opt_sudo  = undef;
my $opt_src;
my $opt_dst;
my $opt_v;
my $opt_d;
my ( $exclude_file, $exclude_handle );

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
    )
    );

usage('Invalid "p" option') if $opt_p < 1;
usage('No "src" option') unless $opt_src;
usage('No "dst" option') unless $opt_dst;
$opt_sudo = $SUDO if defined $opt_sudo && !$opt_sudo;
usage("Can not find \"sudo\" executable ($opt_sudo)")
    if $opt_sudo && !-x $opt_sudo;
usage("Can not find \"rsync\" executable ($opt_rsync)") unless -x $opt_rsync;
usage("No access to temporary directory \"$opt_tmp\"")
    unless -d $opt_tmp && -w $opt_tmp;

# ------------------------------------------------------------------------------
$opt_ropt = join ' ', @ARGV if @ARGV;
$opt_src =~ s/\/*$//g;
$opt_dst =~ s/\/*$//g;

pv( 'Sync "%s" => "%s"...', $opt_src, $opt_dst );

my $spider = AnyEvent::ForkManager->new(
    max_workers => $opt_p + 1,
    on_start    => sub {
        my ( $pm, $pid, $entry ) = @_;
        pd( '[%d] start sync "%s"', $pid, $entry );
    },

    on_finish => sub {
        my ( $pm, $pid, $status, $entry ) = @_;
        pd( '[%d] "%s" sync status: %s', $pid, $entry, $status );
#        exit 0;
    }
);

#step 1: create directories
pv('Creating directory tree...');
sync_entries( [$opt_src], '-a -f"+ */" -f"- *" --numeric-ids'  );

#step 2: collect files
my @entries;
pv('Collect files...');
collect_entries( $opt_src, \@entries );
if (@entries) {
    eval {
        ( $exclude_handle, $exclude_file ) = tempfile(
            'XXXXXXXX',
            SUFFIX => '.' . ( fileparse( $0, qr/\.[^.]*/ ) )[0] || '$$$',
            DIR => $opt_tmp,
        );
    };

    if ($@) {
        print "ERROR: can not create temp file in \"$opt_tmp\":\n$@";
        exit 2;
    }
    print $exclude_handle join( "\n", @entries );
    close $exclude_handle;
}

#step 3: sync directory tree
pv('Sync directory tree...');
unshift @entries, $opt_src;
sync_entries( \@entries );
unlink $exclude_file if $exclude_file;

# ------------------------------------------------------------------------------
sub sync_entries
{
    my ($entries, $rsync_opt) = @_;  
    my $idx = 0;
    foreach my $entry ( @{$entries} ) {
        $spider->start(
            cb => sub {
                my ( $pm, $entry, $idx, $rsync_opt ) = @_;
                sync_entry( $entry, $idx ? undef : $exclude_file, $rsync_opt );
            },
            args => [ $entry, $idx, $rsync_opt ]
        );
        ++$idx;
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
    my ( $entry, $exclude_file, $rsync_opt ) = @_;

    $rsync_opt ||= $opt_ropt;
    my $target = $opt_dst;
    
    if( $entry ne $opt_src )
    {
        my $src = $opt_src;
        $target = $entry;
        $src =~ s/^.+(\/[^\/]+$)/$1/;
        $target =~ s/$opt_src//;
        $target = "$opt_dst$src$target";
    }
       
    my $rsync = '';
    $rsync = "$opt_sudo " if $opt_sudo;
    $rsync .= "$opt_rsync ";
    $rsync .= "--exclude-from=\"$exclude_file\" " if $exclude_file;
    $rsync .= "$rsync_opt \"$entry\" \"$target\"";
    pd( '[%d] %s', $$, $rsync );
    system $rsync;
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
    my ( $dir, $entries ) = @_;

    my $find = '';
    $find = "$opt_sudo " if $opt_sudo;
    $find .= "find \"$dir\" -size +$opt_size -type f |";
    if ( open my $dh, $find ) {
        while ( defined( my $line = <$dh> ) ) {
            chomp $line;
            next unless $line;
            push @{$entries}, $line;
        }
        close $dh;
    }
    else {
        # TODO detect actual locale?
        print "ERROR: can not open \"$find\":\n\t" . decode_utf8($!) . "\n";
        exit 2;
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
    -sudo  [PATH]  use sudo [executable], defaults: NO, executable: '%s'
    -size  SIZE    file size to create separate process, default '%s'
    -p     N       max processes, >0, default: '%d'
    -v             increase verbosity
    -d             print debug information
    --     OPT     rsync options, default: '%s'

EOU
    printf $u, $VERSION, basename($0), $opt_tmp, $opt_rsync, $SUDO, $opt_size, $opt_p, $opt_ropt;
    exit 1;
}

# ------------------------------------------------------------------------------
