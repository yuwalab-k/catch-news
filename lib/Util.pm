package Util;
use strict;
use warnings;
use utf8;
use parent 'Exporter';

use Encode qw(encode);
use JSON::PP qw(decode_json encode_json);
use Time::Piece;

our @EXPORT = qw(
    html html_attr trim url_encode decode_entities
    normalize_color resolve_url favicon_url
    read_json write_json write_text
    now_iso epoch_iso parsed_epoch jst_edition
    item_key date_sort_value min
);

sub html {
    my ($text) = @_;
    $text //= '';
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    return $text;
}

sub html_attr { return html(@_) }

sub trim {
    my ($text) = @_;
    $text //= '';
    $text =~ s/^\s+|\s+$//g;
    return $text;
}

sub url_encode {
    my ($text) = @_;
    $text //= '';
    $text =~ s/([^A-Za-z0-9\-._~])/sprintf("%%%02X", ord($1))/eg;
    return $text;
}

sub decode_entities {
    my ($text) = @_;
    return undef unless defined $text;
    $text =~ s/&lt;/</g;
    $text =~ s/&gt;/>/g;
    $text =~ s/&quot;/"/g;
    $text =~ s/&apos;/'/g;
    $text =~ s/&amp;/&/g;
    $text =~ s/&#x([0-9a-fA-F]+);/chr(hex($1))/eg;
    $text =~ s/&#([0-9]+);/chr($1)/eg;
    return $text;
}

sub normalize_color {
    my ($color) = @_;
    return undef unless defined $color;
    $color = trim($color);
    return uc($color) if $color =~ /^#[0-9a-fA-F]{6}$/;
    return '#' . uc($color) if $color =~ /^[0-9a-fA-F]{6}$/;
    return undef;
}

sub resolve_url {
    my ($base, $url) = @_;
    return undef unless $url;
    return $url if $url =~ m{^https?://};
    return "https:$url" if $url =~ m{^//};

    return undef unless $base =~ m{^(https?)://([^/]+)};
    my ($scheme, $host) = ($1, $2);
    return "$scheme://$host$url" if $url =~ m{^/};

    my $dir = $base;
    $dir =~ s{[#?].*$}{};
    $dir =~ s{/[^/]*$}{/};
    return "$dir$url";
}

sub favicon_url {
    my ($url) = @_;
    return undef unless $url && $url =~ m{^https?://};
    return 'https://www.google.com/s2/favicons?sz=64&domain_url=' . url_encode($url);
}

sub read_json {
    my ($path, $default) = @_;
    return $default unless -e $path;
    open my $fh, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
    local $/;
    my $raw = <$fh>;
    return length($raw) ? decode_json($raw) : $default;
}

sub write_json {
    my ($path, $value) = @_;
    write_text($path, JSON::PP->new->utf8->pretty->canonical->encode($value));
}

sub write_text {
    my ($path, $text) = @_;
    open my $fh, '>:encoding(UTF-8)', $path or die "Cannot write $path: $!";
    print {$fh} $text;
}

sub now_iso {
    return gmtime()->datetime . 'Z';
}

sub epoch_iso {
    my ($epoch) = @_;
    return undef unless $epoch;
    return gmtime($epoch)->datetime . 'Z';
}

sub parsed_epoch {
    my ($date) = @_;
    return undef unless $date;
    return $date if $date =~ /^\d+$/;

    # ISO 8601 with explicit +HH:MM or -HH:MM offset (Time::Piece %z is unreliable for this)
    if ($date =~ /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})([+-])(\d{2}):?(\d{2})$/) {
        my ($dt, $sign, $th, $tm) = ($1, $2, $3, $4);
        my $ep = eval { Time::Piece->strptime($dt, '%Y-%m-%dT%H:%M:%S')->epoch };
        if (defined $ep) {
            my $offset = ($th * 60 + $tm) * 60;
            return $sign eq '+' ? $ep - $offset : $ep + $offset;
        }
    }

    for my $fmt (
        '%Y-%m-%dT%H:%M:%SZ',
        '%Y-%m-%dT%H:%M:%S%z',
        '%Y-%m-%d %H:%M:%S %z',
        '%a, %d %b %Y %H:%M:%S %z',
        '%a, %d %b %Y %H:%M:%S %Z',
    ) {
        my $epoch = eval { Time::Piece->strptime($date, $fmt)->epoch };
        return $epoch if $epoch;
    }
    return undef;
}

sub jst_edition {
    my $slug;
    if (my $forced = $ENV{FORCE_DATETIME}) {
        ($slug = $forced) =~ s/\D//g;
    } else {
        my $jst_epoch = gmtime()->epoch + 9 * 3600;
        my $jst = gmtime($jst_epoch);
        $slug = sprintf('%04d%02d%02d%02d%02d%02d',
            $jst->year, $jst->mon, $jst->mday, $jst->hour, $jst->min, $jst->sec);
    }
    my $date = substr($slug, 0, 8);
    my $time = substr($slug, 8, 6);
    return ($slug, $date, $time);
}

sub item_key {
    my ($item) = @_;
    my $url = $item->{url} || '';
    $url =~ s/[?#].*$//;
    return lc $url || $item->{title};
}

sub date_sort_value {
    my ($item) = @_;
    my $pub = $item->{published_at};
    return 0 unless defined $pub && length $pub;
    return parsed_epoch($pub) || 0;
}

sub min {
    my ($a, $b) = @_;
    return $a < $b ? $a : $b;
}

1;
