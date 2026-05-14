package Fetcher;
use strict;
use warnings;
use utf8;
use parent 'Exporter';

use Encode qw(decode encode);
use HTTP::Tiny;
use JSON::PP qw(decode_json);
use Util qw(decode_entities resolve_url epoch_iso min trim);

our @EXPORT = qw(fetch_source fetch_og_image);

my $http = HTTP::Tiny->new(
    agent   => 'catch-news/0.1',
    timeout => 20,
);

sub fetch_source {
    my ($source) = @_;
    return fetch_rss($source) if $source->{type} eq 'rss';
    return fetch_hackernews($source) if $source->{kind} eq 'hackernews';
    return fetch_devto($source) if $source->{kind} eq 'devto';
    return fetch_qiita($source) if $source->{kind} eq 'qiita';
    die "Unknown API kind '$source->{kind}' for $source->{id}";
}

sub fetch_url {
    my ($url) = @_;
    $url = encode('UTF-8', $url);
    my $res = $http->get($url, { headers => { Accept => '*/*' } });
    die "HTTP $res->{status} for $url" unless $res->{success};
    return decode('UTF-8', $res->{content});
}

sub fetch_json {
    my ($url) = @_;
    my $res = $http->get(encode('UTF-8', $url), { headers => { Accept => 'application/json' } });
    die "HTTP $res->{status} for $url" unless $res->{success};
    return decode_json($res->{content});
}

sub fetch_rss {
    my ($source) = @_;
    my $xml = fetch_url($source->{url});
    my @entries = $xml =~ m{<(item|entry)\b[^>]*>(.*?)</\1>}gis;
    my @items;

    while (@entries) {
        my $tag = shift @entries;
        my $body = shift @entries;
        my $title = xml_text($body, 'title');
        my $link = rss_link($body);
        next unless $title && $link;

        push @items, {
            title        => $title,
            url          => $link,
            published_at => xml_text($body, 'pubDate') || xml_text($body, 'published')
                         || xml_text($body, 'updated') || xml_text($body, 'date'),
            author       => xml_text($body, 'author') || xml_text($body, 'creator'),
            image_url    => rss_image($body),
        };
    }
    return @items;
}

sub fetch_hackernews {
    my ($source) = @_;
    my $endpoint = $source->{url};
    $endpoint = "https://hacker-news.firebaseio.com/v0/$endpoint.json"
        if $endpoint !~ m{^https?://};

    my $ids = fetch_json($endpoint);
    my @items;
    for my $id (@$ids[0 .. min($#$ids, 49)]) {
        my $item = fetch_json("https://hacker-news.firebaseio.com/v0/item/$id.json");
        next unless $item->{title} && ($item->{url} || $item->{id});
        push @items, {
            title        => $item->{title},
            url          => $item->{url} || "https://news.ycombinator.com/item?id=$item->{id}",
            published_at => epoch_iso($item->{time}),
            score        => $item->{score},
            author       => $item->{by},
        };
    }
    return @items;
}

sub fetch_devto {
    my ($source) = @_;
    my $rows = fetch_json($source->{url});
    return map {
        +{
            title        => $_->{title},
            url          => $_->{url},
            published_at => $_->{published_at} || $_->{created_at},
            author       => $_->{user}{name},
            score        => $_->{positive_reactions_count},
            image_url    => $_->{cover_image} || $_->{social_image},
        }
    } grep { $_->{title} && $_->{url} } @$rows;
}

sub fetch_qiita {
    my ($source) = @_;
    my $rows = fetch_json($source->{url});
    return map {
        +{
            title        => $_->{title},
            url          => $_->{url},
            published_at => $_->{created_at} || $_->{updated_at},
            author       => $_->{user}{id},
            score        => $_->{likes_count},
        }
    } grep { $_->{title} && $_->{url} } @$rows;
}

sub fetch_og_image {
    my ($url) = @_;
    return undef unless $url && $url =~ m{^https?://};
    my $html = eval { fetch_url($url) };
    return undef if !$html;

    my $image;
    if ($html =~ m{<meta\b[^>]*(?:property|name)=["'](?:og:image|twitter:image)["'][^>]*content=["']([^"']+)["'][^>]*>}is) {
        $image = decode_entities($1);
    } elsif ($html =~ m{<meta\b[^>]*content=["']([^"']+)["'][^>]*(?:property|name)=["'](?:og:image|twitter:image)["'][^>]*>}is) {
        $image = decode_entities($1);
    }
    return resolve_url($url, $image);
}

sub xml_text {
    my ($body, $name) = @_;
    return undef unless $body =~ m{<(?:(?:\w+:)?\Q$name\E)\b[^>]*>(.*?)</(?:(?:\w+:)?\Q$name\E)>}is;
    my $text = $1;
    $text =~ s{<!\[CDATA\[(.*?)\]\]>}{$1}gis;
    $text =~ s/<[^>]+>//g;
    return trim(decode_entities($text));
}

sub rss_link {
    my ($body) = @_;
    my $link = xml_text($body, 'link');
    return $link if $link;
    return decode_entities($1) if $body =~ m{<link\b[^>]*href=["']([^"']+)["'][^>]*/?>}is;
    return undef;
}

sub rss_image {
    my ($body) = @_;
    return decode_entities($1) if $body =~ m{<media:thumbnail\b[^>]*url=["']([^"']+)["'][^>]*/?>}is;
    return decode_entities($1) if $body =~ m{<media:content\b[^>]*url=["']([^"']+)["'][^>]*/?>}is;
    return decode_entities($1) if $body =~ m{<enclosure\b[^>]*url=["']([^"']+)["'][^>]*type=["']image/[^"']+["'][^>]*/?>}is;
    return undef;
}

1;
