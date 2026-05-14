#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use FindBin;
use Time::Piece;
use lib "$FindBin::Bin/../lib";

use Util;
use Fetcher;
use Source;
use Renderer;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $ROOT          = '.';
my $MAX_ITEMS     = $ENV{MAX_ITEMS} || 500;
my $FETCH_OG_IMAGES = exists $ENV{FETCH_OG_IMAGES} ? $ENV{FETCH_OG_IMAGES} : 0;

# SINCE_DATETIME=YYYYMMDDHHММ (JST) — treat articles published after this as new even if already seen
my $SINCE_EPOCH = do {
    my $s = $ENV{SINCE_DATETIME};
    if ($s) {
        $s =~ s/\D//g;
        $s = sprintf('%-14s', $s) =~ s/ /0/gr;
        my ($Y, $M, $D, $h, $m) = ($s =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})/);
        my $ep = eval { Time::Piece->strptime("$Y-$M-${D}T${h}:${m}:00", '%Y-%m-%dT%H:%M:%S')->epoch };
        $ep ? $ep - 9 * 3600 : undef;  # input is JST, convert to UTC epoch
    } else {
        undef;
    }
};

my @CATEGORIES = (
    { id => 'knowledge', label => 'Knowledge' },
    { id => 'official',  label => 'Official' },
    { id => 'security',  label => 'Security' },
);

make_path("$ROOT/data", "$ROOT/dist", "$ROOT/state");

my $state_path = "$ROOT/state/seen.json";
my $data_path  = "$ROOT/data/items.json";

my $state = read_json($state_path, { seen => {}, fetched_at => {} });
my $items = read_json($data_path,  []);

my @sources = (parse_rss_sources(), parse_api_sources());
die "No sources configured. Set RSS_SOURCES and/or API_SOURCES.\n" unless @sources;
my %source_by_id = map { $_->{id} => $_ } @sources;

my @new_items;
for my $source (@sources) {
    my $now = now_iso();
    eval {
        my @fetched = fetch_source($source);
        for my $item (@fetched) {
            my $key = item_key($item);
            next unless $key;
            if ($state->{seen}{$key}) {
                if (defined $SINCE_EPOCH) {
                    my $pub = parsed_epoch($item->{published_at} || '');
                    next unless defined $pub && $pub >= $SINCE_EPOCH;
                } else {
                    next;
                }
            }

            $item->{id}           = sha256_hex($key);
            $item->{source_id}    = $source->{id};
            $item->{source}       = $source->{name};
            $item->{source_type}  = $source->{type};
            $item->{source_color} = source_color($source);
            $item->{source_icon}  = source_icon($source);
            $item->{source_home}  = source_home($source);
            $item->{category}     = source_category($source);
            $item->{image_url} ||= fetch_og_image($item->{url}) if $FETCH_OG_IMAGES;
            $item->{fetched_at}   = $now;

            push @new_items, $item;
            $state->{seen}{$key} = $now;
        }
        $state->{fetched_at}{$source->{id}} = {
            last_attempt_at => $now,
            last_success_at => $now,
            last_error      => undef,
        };
        1;
    } or do {
        my $error = $@ || 'unknown error';
        warn "Failed: $source->{id}: $error\n";
        $state->{fetched_at}{$source->{id}} = {
            last_attempt_at => $now,
            last_success_at => $state->{fetched_at}{$source->{id}}{last_success_at},
            last_error      => "$error",
        };
    };
}

push @$items, @new_items;
apply_source_meta($items, \%source_by_id);
@$items = sort { date_sort_value($b) <=> date_sort_value($a) } @$items;
splice @$items, $MAX_ITEMS if @$items > $MAX_ITEMS;

my ($edition_slug, $edition_date, $edition_time) = jst_edition();
my $edition_title = do {
    (my $d = $edition_date) =~ s/^(\d{4})(\d{2})(\d{2})$/$1-$2-$3/;
    (my $t = $edition_time) =~ s/^(\d{2})(\d{2})(\d{2})$/$1:$2:$3/;
    "$d $t";
};

my %cat_count;
for my $item (@new_items) {
    $cat_count{$item->{category} || 'knowledge'}++;
}

my $editions_path = "$ROOT/data/editions.json";
my $editions = read_json($editions_path, []);
@$editions = grep { $_->{slug} ne $edition_slug } @$editions;
unshift @$editions, {
    slug         => $edition_slug,
    title        => $edition_title,
    date         => $edition_date,
    time         => $edition_time,
    generated_at => now_iso(),
    by_category  => \%cat_count,
};

write_json($data_path,    $items);
write_json($state_path,   $state);
write_json($editions_path, $editions);

my @cats_data;
for my $cat (@CATEGORIES) {
    my @cat_items = grep { ($_->{category} || 'knowledge') eq $cat->{id} } @new_items;
    @cat_items = sort { date_sort_value($b) <=> date_sort_value($a) } @cat_items;
    push @cats_data, { %$cat, items => \@cat_items };
}

make_path("$ROOT/dist/articles");
write_edition_html("$ROOT/dist/articles/$edition_slug.html", $edition_title, \@cats_data, '../', 0);
write_edition_html("$ROOT/dist/index.html",                  $edition_title, \@cats_data, './', 1);
write_archive_html("$ROOT/dist/archive.html", $editions);
write_text("$ROOT/dist/style.css",  static_css());
write_text("$ROOT/dist/.nojekyll", "");

print "Edition: $edition_title\n";
print "Fetched sources: " . scalar(@sources) . "\n";
print "New items: " . scalar(@new_items) . "\n";
print "Total items: " . scalar(@$items) . "\n";
