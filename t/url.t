package test::Karasuma::URL;
use strict;
use warnings;
use Path::Class;
use lib file(__FILE__)->dir->parent->subdir('lib')->stringify;
use lib glob file(__FILE__)->dir->parent->subdir('modules', '*', 'lib')->stringify;
use base qw(Test::Class);
use Test::More;
use Karasuma::URL;

sub _parse_url : Test(2) {
    for (
        [q<http://foo.bar/baz/hoge?abc&def=abc#xyz> =>
         q<http://foo.bar/baz/hoge?def=abc#xyz>],
        [qq<http://\x{4e00}:\x{4e00}\@\x{4e00}/\x{4e00}/\x{4e00}?\x{4e00}=\x{4e00}#\x{4e00}> =>
         q<http://%E4%B8%80:%E4%B8%80@%E4%B8%80/%E4%B8%80/%E4%B8%80?%E4%B8%80=%E4%B8%80#%E4%B8%80>],
    ) {
        my $u = Karasuma::URL->parse_url($_->[0]);
        is $u->as_absurl, $_->[1];
    }
}

sub _url_authority : Test(10) {
    for (
        [{scheme => 'http', hostname => 'foobar.test', port => 80}, 'foobar.test'],
        [{scheme => 'https', hostname => 'foobar.test', port => 80}, 'foobar.test:80'],
        [{hostname => 'foobar.test', port => 80}, 'foobar.test:80'],
        [{hostname => 'foobar.test', port => 81}, 'foobar.test:81'],
        [{hostname => 'foobar.test', port => ''}, 'foobar.test'],
        [{hostname => 'foobar.test', port => 'abc'}, 'foobar.test:0'],
        [{user => 'a@b'} => 'a%40b@localhost'],
        [{user => 'a@b', password => ''} => 'a%40b:@localhost'],
        [{user => 'a@b', hostname => 'xyz'} => 'a%40b@xyz'],
        [{scheme => 'http', user => 'a@b', hostname => 'xyz', port => 80} => 'a%40b@xyz'],
    ) {
        my $u = Karasuma::URL->new(%{$_->[0]});
        is $u->url_authority, $_->[1];
    }
}

sub _append_path_none : Test(1) {
    my $u = Karasuma::URL->new(path => ['foo', '']);
    $u->append_path;
    is $u->url_path, q</foo/>;
}

sub _append_path_one : Test(1) {
    my $u = Karasuma::URL->new(path => ['foo', '']);
    $u->append_path('bar');
    is $u->url_path, q</foo/bar>;
}

sub _append_path_one_2 : Test(1) {
    my $u = Karasuma::URL->new(path => ['foo', 'bar']);
    $u->append_path('bar');
    is $u->url_path, q</foo/bar/bar>;
}

sub _append_path_two : Test(1) {
    my $u = Karasuma::URL->new(path => ['foo', '']);
    $u->append_path('bar', 'baz');
    is $u->url_path, q</foo/bar/baz>;
}

sub _append_path_chained : Test(1) {
    my $u = Karasuma::URL->new(path => ['foo', '']);
    is $u->append_path('bar', 'baz')->append_path('baz')->url_path,
        q</foo/bar/baz/baz>;
}

sub _qparams_escape : Test(2) {
    my $u = Karasuma::URL->new(
        qparams => {
            'Aa\'bw"&<>"#|`~{[]}?' . "\x00\x{4000}" => 'fw?g"\'w<&>#|`~{[]}' . "\x{2000}\x00",
        },
    );
    is $u->url_query, q<?Aa%27bw%22%26%3C%3E%22%23%7C%60~%7B%5B%5D%7D%3F%00%E4%80%80=fw%3Fg%22%27w%3C%26%3E%23%7C%60~%7B%5B%5D%7D%E2%80%80%00>;
    is $u->as_absurl, q</?Aa%27bw%22%26%3C%3E%22%23%7C%60~%7B%5B%5D%7D%3F%00%E4%80%80=fw%3Fg%22%27w%3C%26%3E%23%7C%60~%7B%5B%5D%7D%E2%80%80%00>;
}

sub _qparams_multiple_values : Test(1) {
    my $u = Karasuma::URL->new;
    $u->qparams->{foo} = ['abc', 'def' . "\x{1000}", 'abc'];
    $u->qparams->{bar} = 124;
    $u->qparams->{baz} = undef;
    is $u->url_query, q<?bar=124&foo=abc&foo=def%E1%80%80&foo=abc>;
}

sub _query_encoding : Test(3) {
    my $u = Karasuma::URL->new(qparams => {"ab\x{3001}" => "\x{4e00}ab"});
    is $u->query_encoding, 'utf-8';
    $u->query_encoding('euc-jp');
    is $u->query_encoding, 'euc-jp';
    is $u->url_query, '?ab%A1%A2=%B0%ECab';
}

sub _set_qparams : Test(1) {
    my $u = Karasuma::URL->new(
        qparams => {a => 1},
    );
    $u->set_qparam(a => 2);
    is $u->stringify, q</?a=2>;
}

sub _clear_qparams : Test(1) {
    my $u = Karasuma::URL->new(
        qparams => {a => 1, b => 2},
    );
    is $u->clear_qparams->stringify, q</>;
}

sub _clone : Test(2) {
    my $url = Karasuma::URL->new({
        path => [qw/path to engine/],
        qparams => {a => 'b', c => 'd'},
        fragment => 'abc',
    });

    my $clone = $url->clone;
    $clone->path([qw/another path/]);
    $clone->qparams->{c} = 'e';
    
    is $url->stringify, q</path/to/engine?a=b&c=d#abc>;
    is $clone->stringify, q</another/path?a=b&c=e#abc>;
}

sub _clone_locale_1 : Test(3) {
    my $locale = {hoge => 1};
    
    my $url = Karasuma::URL->new({
        locale => $locale,
        path => [qw/path to engine/],
        qparams => {a => 'b', c => 'd'},
        fragment => 'abc',
    });

    my $clone = $url->clone;

    is $url->{locale}, $locale;
    is $clone->{locale}, $locale;
    isnt $url->{path}, $clone->{path};
}

sub _clone_locale_2 : Test(2) {
    my $url = Karasuma::URL->new({
        path => [qw/path to engine/],
        qparams => {a => 'b', c => 'd'},
        fragment => 'abc',
    });

    my $clone = $url->clone;

    is $url->{locale}, undef;
    is $clone->{locale}, undef;
}

sub _as_abspath : Test(9) {
    my $u1 = Karasuma::URL->new;
    is $u1->as_abspath, q</>;
    is $u1->as_scheme_relative_url, q</>;
    
    my $u2 = Karasuma::URL->new(qparams => {a => 3}, fragment => 'hoge');
    is $u2->as_abspath, q{/?a=3#hoge};
    is $u2->as_scheme_relative_url, q{/?a=3#hoge};
    is $u2->as_absurl, q{/?a=3#hoge};
    
    my $u3 = Karasuma::URL->new(qparams => {a => 3}, fragment => 'hoge');
    $u3->hostname('hogehoge');
    is $u3->as_abspath, q{/?a=3#hoge};
    is $u3->as_scheme_relative_url, q{//hogehoge/?a=3#hoge};

    my $u4 = Karasuma::URL->new(qparams => {a => 3}, fragment => 'hoge');
    $u4->scheme('https');
    is $u4->as_abspath, q{/?a=3#hoge};
    is $u4->as_scheme_relative_url, q{//localhost/?a=3#hoge};
}

__PACKAGE__->runtests;

1;
