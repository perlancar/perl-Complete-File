#!perl

use 5.010;
use strict;
use warnings;

use File::chdir;
use File::Temp qw(tempdir);
use Test::More;

use Complete::Util qw(complete_file);

sub mkfiles { do { open my($fh), ">$_" or die "Can't mkfile $_" } for @_ }
sub mkdirs  { do { mkdir $_ or die "Can't mkdir $_" } for @_ }

local $Complete::Setting::OPT_DIG_LEAF = 0;

my $rootdir = tempdir(CLEANUP=>1);
$CWD = $rootdir;
mkfiles(qw(a ab abc ac bb d .h1));
mkdirs (qw(dir1 dir2 foo));
mkdirs (qw(dir1/sub1 dir2/sub2 dir2/sub3));
mkfiles(qw(foo/f1 foo/f2 foo/g));

mkdirs (qw(Food));
mkdirs (qw(Food/Sub4));
mkfiles(qw(Food/f1 Food/F2));

mkfiles(qw(Food/Sub4/one Food/Sub4/one-two Food/Sub4/one_three));

test_complete(
    word      => '',
    result    => [qw(.h1 Food/ a ab abc ac bb d dir1/ dir2/ foo/)],
);
test_complete(
    word      => 'a',
    result    => [qw(a ab abc ac)],
);
test_complete(
    name      => 'dir + file',
    word      => 'd',
    result    => [qw(d dir1/ dir2/)],
);
test_complete(
    name       => 'filter (file only)',
    word       => 'd',
    other_args => [filter=>'-d'],
    result     => [qw(d)],
);
test_complete(
    name       => 'dir only, use |, not very meaningful test',
    word       => 'd',
    other_args => [filter=>'d|-f'],
    result     => [qw(dir1/ dir2/)],
);
test_complete(
    name       => 'code filter',
    word       => '',
    other_args => [filter=>sub {my $res=(-d $_[0]) && $_[0] =~ m!\./f!}],
    result     => [qw(foo/)],
);
test_complete(
    name      => 'subdir 1',
    word      => 'foo/',
    result    => ["foo/f1", "foo/f2", "foo/g"],
);
test_complete(
    name      => 'subdir 2',
    word      => 'foo/f',
    result    => ["foo/f1", "foo/f2"],
);

subtest "opt: ci" => sub {
    test_complete(
        word      => 'f',
        ci        => 1,
        result    => ["Food/", "foo/"],
    );
    test_complete(
        word      => 'F',
        ci        => 1,
        result    => ["Food/", "foo/"],
    );
    test_complete(
        word      => 'Food/f',
        ci        => 1,
        result    => ["Food/F2", "Food/f1"],
    );
    # XXX test foo/ and Foo/ exists, but this requires that fs is case-sensitive
};

subtest "opt: exp_im_path" => sub {
    test_complete(
        word   => 'F/S/o',
        exp_im_path => 1,
        result => ["Food/Sub4/one", "Food/Sub4/one-two", "Food/Sub4/one_three"],
    );
};

subtest "opt: map_case" => sub {
    test_complete(
        word   => 'Food/Sub4/one-',
        map_case => 0,
        result => ["Food/Sub4/one-two"],
    );
    test_complete(
        word   => 'Food/Sub4/one-',
        map_case => 1,
        result => ["Food/Sub4/one-two", "Food/Sub4/one_three"],
    );
    test_complete(
        word   => 'Food/Sub4/one_',
        map_case => 1,
        result => ["Food/Sub4/one-two", "Food/Sub4/one_three"],
    );
};

# XXX test ../blah
# XXX test /abs
# XXX test ~/blah and ~user/blah

# XXX test opt: starting_path
# XXX test opt: allow_dot=0
# XXX test opt: handle_tilde=0

DONE_TESTING:
$CWD = "/";
done_testing();

sub test_complete {
    my (%args) = @_;

    my $name = $args{name} // $args{word};
    my $res = complete_file(
        word=>$args{word}, array=>$args{array},
        ci=>$args{ci} // 0,
        map_case=>$args{map_case} // 0,
        exp_im_path=>$args{exp_im_path} // 0,
        @{ $args{other_args} // [] });
    is_deeply($res, $args{result}, "$name (result)") or diag explain($res);
}
