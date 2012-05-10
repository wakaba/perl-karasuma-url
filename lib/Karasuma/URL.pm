package Karasuma::URL;
use strict;
use warnings;
our $VERSION = '1.0';
use URL::PercentEncode;
use Encode;
use Storable qw/dclone/;

((eval sprintf q{
    sub %s {
        if (@_ > 1) {
            $_[0]->{%s} = $_[1];
        }
        return $_[0]->{%s};
    }
    1;
}, $_, $_, $_) or die $@) for qw(
    scheme
    user
    password
    hostname
    port
    path
    extension
    qparams
    fragment

    preserve_undef_qparams
    preserve_empty_qparams
);

# XXX list: path

sub new {
    my $class = shift;
    my $self = ((defined $_[0] and ref $_[0] eq 'HASH') ? $_[0] : {@_});
    bless $self, $class;
    
    # XXX list

    # Don't use List::Rubyish as blessing is too heavy (ack: cho45)
    $self->{path} ||= [];
    $self->{qparams} ||= {};
    
    # XXX initial value normalization

    $self->use_tls(delete $self->{use_tls}) if exists $self->{use_tls};

    return $self;
}

sub parse_url {
    my ($class, $url) = @_;
    $url = '' unless defined $url;
    my $u = $class->new;

    if ($url =~ s{^([0-9A-Za-z+-.]+):}{}) {
        $u->scheme($1);
    }
    
    if ($url =~ s{\#(.*)}{}s) {
        $u->fragment(percent_decode_c $1);
    }
    
    if ($url =~ s{\?(.*)}{}s) {
        # BUG: Does not support duplicate qparams...
        %{$u->qparams} = map { $_->[0] => $_->[1] } map { [map { percent_decode_c $_ } split /=/, $_, 2] } split /[&;]/, $1;
    }

    if ($url =~ s{^//([^/]*)}{}) {
        my $authority = $1;
        if ($authority =~ s{:([0-9]*)$}{}) {
            $u->port($1);
        }
        if ($authority =~ s{([^\@]*)\z}{}) {
            $u->hostname(percent_decode_c $1);
        }
        if ($authority =~ s/\@\z//) {
            if ($authority =~ s{^([^:]*)}{}) {
                $u->user(percent_decode_c $1);
            }
            if ($authority =~ s/^://) {
                $u->password(percent_decode_c $authority);
            }
        }
    }

    @{$u->path} = map { percent_decode_c $_ } split m{/}, $url, -1;
    shift @{$u->path};
    
    return $u;
}

sub url_scheme {
    my $self = shift;
    
    # XXX setter
    
    my $scheme = $self->scheme;
    if (defined $scheme) {
        return percent_encode_c $scheme;
    } else {
        return undef;
    }
}

sub use_tls {
    my $self = shift;

    if (@_) {
        my $scheme = $self->scheme || 'http';
        if (shift) {
            $self->scheme({
                http => 'https',
                https => 'https',
            }->{$scheme} or die "no TLS-enabled variant for $scheme found");
        } else {
            $self->scheme({
                http => 'http',
                https => 'http',
                ugomemo => 'ugomemo',
                mailto => 'mailto',
            }->{$scheme} or die "no TLS-disabled variant for $scheme found");
        }

        return unless defined wantarray;
    }

    my $scheme = $self->scheme;
    
    if (not defined $scheme) {
        return 0;
    } else {
        return {
            https => 1,
        }->{$scheme} || 0;
    }
}

sub url_host {
    my $self = shift;

    my $user = $self->user;
    my $password = $self->password;
    my $hostname = $self->hostname;
    my $port = $self->port;
    
    if (defined $hostname or defined $port or defined $user or defined $password) {
        my $prefix = '';
        if (defined $user or defined $password) {
            $prefix = defined $user ? percent_encode_c $user : '';
            if (defined $password) {
                $prefix .= ':' . percent_encode_c $password;
            }
            $prefix .= '@';
        }
        $hostname = 'localhost' unless defined $hostname;
        if (defined $port and length $port) {
            my $scheme = $self->scheme;
            if (defined $scheme and $scheme =~ /\A[Hh][Tt][Tt][Pp]\z/ and
                ($port eq '80' or $port eq '')) {
                return $prefix . percent_encode_c $hostname;
            }
            return $prefix . sprintf '%s:%d', percent_encode_c($hostname), $port;
        } else {
            return $prefix . percent_encode_c $hostname;
        }
    } else {
        return undef;
    }
}

sub url_authority {
    my $self = shift;
    
    return $self->url_host;
}

sub url_path {
    my $self = shift;

    # XXX setter
    
    my @path = ('', @{$self->path});
    push @path, '' if @path == 1;
    my $path = join '/', map { percent_encode_c $_ } @path;
    
    return $path;
}

sub append_path {
    my $self = shift;
    if (@_) {
        my $path = $self->path;
        pop @$path if @$path and not length $path->[-1];
        push @$path, @_;
    }
    return $self;
}

sub query_encoding {
    my $self = shift;
    if (@_) {
        $self->{query_encoding} = shift;
    }
    return $self->{query_encoding} || 'utf-8';
}

sub url_query {
    my $self = shift;

    # XXX setter

    my @query = (%{$self->qparams});
    my $preserve_empty = $self->preserve_empty_qparams;
    my $preserve_undef = $self->preserve_undef_qparams;
    
    my $qparams = [];
    my $encoding = $self->query_encoding;
    while (@query) {
        my $name = '' . shift @query;
        my $value = shift @query;
        my @value;
        for my $v (
            (defined $value and ref $value eq 'ARRAY')
                ? (@$value)
                : ($value)
        ) {
            $v = '' . $v if defined $v;
            if (not defined $v) {
                next unless $preserve_undef;
                $v = '';
            } elsif ($v eq '') {
                next unless $preserve_empty;
            }
            
            $v = percent_encode_b encode $encoding, $v;
            push @value, $v;
        }
        
        if (@value) {
            $name = percent_encode_b encode $encoding, $name;
            push @$qparams, [$name => \@value];
        }
    }
    
    if (@$qparams) {
        return '?' . join '&', map {
            my $nv = $_;
            (map { $nv->[0] . '=' . $_ } @{$nv->[1]});
        } sort {$a->[0] cmp $b->[0]} @$qparams;
    } else {
        return undef;
    }
}

sub set_qparam {
    my ($self, $n, $v) = @_;
    $self->qparams->{$n} = $v;
    return $self;
}

sub clear_qparams {
    my $self = shift;
    %{$self->qparams} = ();
    return $self;
}

sub url_path_query {
    my $self = shift;

    # XXX setter

    my $path = $self->url_path;
    my $query = $self->url_query;
    $query = '' unless defined $query;
    return $path . $query;
}

sub url_fragment {
    my $self = shift;
    
    my $f = $self->fragment;
    if (defined $f) {
        return '#' . percent_encode_c $f;
    } else {
        return undef;
    }
}

sub url_path_query_fragment {
    my $self = shift;

    # XXX setter

    my $pq = $self->url_path_query;
    my $f = $self->url_fragment;
    $f = '' unless defined $f;
    return $pq . $f;
}

sub url_reference {
    my $self = shift;

    my $r = '';
    
    my $scheme = $self->url_scheme;
    if (defined $scheme) {
        $r .= $scheme . ':';
    }

    my $authority = $self->url_authority;
    if (defined $authority) {
        $r .= '//' . $authority;
    } elsif (length $r) {
        $r .= '//localhost';
    }

    $r .= $self->url_path_query_fragment;

    return $r;
}

*stringify = \&url_reference;

*as_abspath = \&url_path_query_fragment;

# --- Absolute URL ---

sub absolutize { } # no action if not possible

sub as_absurl {
    my $self = shift;
    $self->absolutize;
    return $self->stringify;
}

sub as_scheme_relative_url {
    my $self = shift;
    my $url = $self->as_absurl;
    $url =~ s/^[^:]+://;
    return $url;
}

# --- Cloning ---

sub clone {
    my $self = shift;
    my $locale = $self->{locale};
    local $self->{locale} = undef;
    my $clone = dclone $self;
    $clone->{locale} = $locale;
    return $clone;
}

1;
