package Complete::File;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Complete::Setting;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       complete_file
               );

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Completion routines related to files',
};

$SPEC{complete_file} = {
    v => 1.1,
    summary => 'Complete file and directory from local filesystem',
    args_rels => {
        choose_one => [qw/filter file_regex_filter/],
    },
    args => {
        word => {
            schema  => [str=>{default=>''}],
            req     => 1,
            pos     => 0,
        },
        ci => {
            summary => 'Case-insensitive matching',
            schema  => 'bool',
        },
        fuzzy => {
            summary => 'Fuzzy matching',
            schema  => ['int*', min=>0],
        },
        map_case => {
            schema  => 'bool',
        },
        exp_im_path => {
            schema  => 'bool',
        },
        dig_leaf => {
            schema  => 'bool',
        },
        filter => {
            summary => 'Only return items matching this filter',
            description => <<'_',

Filter can either be a string or a code.

For string filter, you can specify a pipe-separated groups of sequences of these
characters: f, d, r, w, x. Dash can appear anywhere in the sequence to mean
not/negate. An example: `f` means to only show regular files, `-f` means only
show non-regular files, `drwx` means to show only directories which are
readable, writable, and executable (cd-able). `wf|wd` means writable regular
files or writable directories.

For code filter, you supply a coderef. The coderef will be called for each item
with these arguments: `$name`. It should return true if it wants the item to be
included.

_
            schema  => ['any*' => {of => ['str*', 'code*']}],
        },
        file_regex_filter => {
            summary => 'Filter shortcut for file regex',
            description => <<'_',

This is a shortcut for constructing a filter. So instead of using `filter`, you
use this option. This will construct a filter of including only directories or
regular files, and the file must match a regex pattern. This use-case is common.

_
            schema => 're*',
        },
        starting_path => {
            schema  => 'str*',
            default => '.',
        },
        handle_tilde => {
            schema  => 'bool',
            default => 1,
        },
        allow_dot => {
            summary => 'If turned off, will not allow "." or ".." in path',
            description => <<'_',

This is most useful when combined with `starting_path` option to prevent user
going up/outside the starting path.

_
            schema  => 'bool',
            default => 1,
        },
    },
    result_naked => 1,
    result => {
        schema => 'array',
    },
};
sub complete_file {
    require Complete::Path;
    require File::Glob;

    my %args   = @_;
    my $word   = $args{word} // "";
    my $ci          = $args{ci} // $Complete::Setting::OPT_CI;
    my $fuzzy       = $args{fuzzy} // $Complete::Setting::OPT_FUZZY;
    my $map_case    = $args{map_case} // $Complete::Setting::OPT_MAP_CASE;
    my $exp_im_path = $args{exp_im_path} // $Complete::Setting::OPT_EXP_IM_PATH;
    my $dig_leaf    = $args{dig_leaf} // $Complete::Setting::OPT_DIG_LEAF;
    my $handle_tilde = $args{handle_tilde} // 1;
    my $allow_dot   = $args{allow_dot} // 1;
    my $filter = $args{filter};

    # if word is starts with "~/" or "~foo/" replace it temporarily with user's
    # name (so we can restore it back at the end). this is to mimic bash
    # support. note that bash does not support case-insensitivity for "foo".
    my $result_prefix;
    my $starting_path = $args{starting_path} // '.';
    if ($handle_tilde && $word =~ s!\A(~[^/]*)/!!) {
        $result_prefix = "$1/";
        my @dir = File::Glob::glob($1); # glob will expand ~foo to /home/foo
        return [] unless @dir;
        $starting_path = $dir[0];
    } elsif ($allow_dot && $word =~ s!\A((?:\.\.?/+)+|/+)!!) {
        # just an optimization to skip sequences of '../'
        $starting_path = $1;
        $result_prefix = $1;
        $starting_path =~ s#/+\z## unless $starting_path =~ m!\A/!;
    }

    # bail if we don't allow dot and the path contains dot
    return [] if !$allow_dot &&
        $word =~ m!(?:\A|/)\.\.?(?:\z|/)!;

    # prepare list_func
    my $list = sub {
        my ($path, $intdir, $isint) = @_;
        opendir my($dh), $path or return undef;
        my @res;
        for (sort readdir $dh) {
            # skip . and .. if leaf is empty, like in bash
            next if ($_ eq '.' || $_ eq '..') && $intdir eq '';
            next if $isint && !(-d "$path/$_");
            push @res, $_;
        }
        \@res;
    };

    # prepare filter_func
    if ($filter && !ref($filter)) {
        my @seqs = split /\s*\|\s*/, $filter;
        $filter = sub {
            my $name = shift;
            my @st = stat($name) or return 0;
            my $mode = $st[2];
            my $pass;
          SEQ:
            for my $seq (@seqs) {
                my $neg = sub { $_[0] };
                for my $c (split //, $seq) {
                    if    ($c eq '-') { $neg = sub { $_[0] ? 0 : 1 } }
                    elsif ($c eq 'r') { next SEQ unless $neg->($mode & 0400) }
                    elsif ($c eq 'w') { next SEQ unless $neg->($mode & 0200) }
                    elsif ($c eq 'x') { next SEQ unless $neg->($mode & 0100) }
                    elsif ($c eq 'f') { next SEQ unless $neg->($mode & 0100000)}
                    elsif ($c eq 'd') { next SEQ unless $neg->($mode & 0040000)}
                    else {
                        die "Unknown character in filter: $c (in $seq)";
                    }
                }
                $pass = 1; last SEQ;
            }
            $pass;
        };
    } elsif (!$filter && $args{file_regex_filter}) {
        $filter = sub {
            my $name = shift;
            return 1 if -d $name;
            return 0 unless -f _;
            return 1 if $name =~ $args{file_regex_filter};
            0;
        };
    }

    Complete::Path::complete_path(
        word => $word,

        ci => $ci,
        fuzzy => $fuzzy,
        map_case => $map_case,
        exp_im_path => $exp_im_path,
        dig_leaf => $dig_leaf,

        list_func => $list,
        is_dir_func => sub { -d $_[0] },
        filter_func => $filter,
        starting_path => $starting_path,
        result_prefix => $result_prefix,
    );
}

1;
# ABSTRACT:

=head1 DESCRIPTION


=head1 SEE ALSO

L<Complete>

Other C<Complete::*> modules.
