package Source;
use strict;
use warnings;
use utf8;
use parent 'Exporter';

use Encode qw(decode);
use Util qw(trim normalize_color favicon_url);

our @EXPORT = qw(
    parse_rss_sources parse_api_sources
    apply_source_meta
    source_color source_icon source_home source_category
);

sub parse_rss_sources {
    return parse_line_sources($ENV{RSS_SOURCES}, [qw(id name url)], 'rss', 3);
}

sub parse_api_sources {
    return parse_line_sources($ENV{API_SOURCES}, [qw(id name kind url)], 'api', 4);
}

sub parse_line_sources {
    my ($value, $fields, $type, $required_count) = @_;
    return () unless defined $value && length $value;
    $value = decode('UTF-8', $value);

    my @sources;
    for my $line (split /\r?\n|;;/, $value) {
        $line =~ s/^\s+|\s+$//g;
        next if !$line || $line =~ /^#/;

        my @parts = map { trim($_) } split /\|/, $line;
        die "Invalid $type source: $line\n"
            if @parts < $required_count || grep { !defined || $_ eq '' } @parts[0 .. $required_count - 1];

        my %source;
        @source{@$fields} = @parts[0 .. scalar(@$fields) - 1];
        $source{color} = normalize_color($parts[$required_count])
            if defined $parts[$required_count] && $parts[$required_count] ne '';

        my $icon_or_category = $parts[$required_count + 1];
        my $category         = $parts[$required_count + 2];
        if (defined $icon_or_category && normalize_category($icon_or_category)
                && (!defined $category || $category eq '')) {
            $source{category} = normalize_category($icon_or_category);
        } else {
            $source{icon}     = $icon_or_category
                if defined $icon_or_category && $icon_or_category ne '';
            $source{category} = normalize_category($category)
                if defined $category && $category ne '';
        }
        $source{category} ||= 'knowledge';
        $source{type} = $type;
        push @sources, \%source;
    }
    return @sources;
}

sub apply_source_meta {
    my ($items, $source_by_id) = @_;
    for my $item (@$items) {
        my $source = $source_by_id->{$item->{source_id} || ''};
        next unless $source;
        $item->{source}       = $source->{name};
        $item->{source_color} = source_color($source);
        $item->{source_icon}  = source_icon($source);
        $item->{source_home}  = source_home($source);
        $item->{category}     = source_category($source);
        delete $item->{comments_url};
    }
}

sub source_color {
    my ($source) = @_;
    return normalize_color($source->{color}) if $source->{color};
    return color_from_id($source->{id});
}

sub source_icon {
    my ($source) = @_;
    return $source->{icon} if $source->{icon};
    return favicon_url(source_home($source));
}

sub source_home {
    my ($source) = @_;
    return $source->{url} if $source->{url} && $source->{url} =~ m{^https?://};
    return 'https://news.ycombinator.com/' if ($source->{kind} || '') eq 'hackernews';
    return 'https://dev.to/'              if ($source->{kind} || '') eq 'devto';
    return 'https://qiita.com/'           if ($source->{kind} || '') eq 'qiita';
    return undef;
}

sub source_category {
    my ($source) = @_;
    return normalize_category($source->{category}) || 'knowledge';
}

sub normalize_category {
    my ($category) = @_;
    return undef unless defined $category;
    $category = lc trim($category);
    return $category if $category =~ /^(knowledge|official|security)$/;
    return undef;
}

sub color_from_id {
    my ($id) = @_;
    my @palette = (
        '#2563EB', '#059669', '#D97706', '#DC2626', '#7C3AED',
        '#0891B2', '#4F46E5', '#BE123C', '#0F766E', '#9333EA',
        '#64748B', '#B45309',
    );
    my $sum = 0;
    $sum += ord($_) for split //, ($id || '');
    return $palette[$sum % @palette];
}

1;
