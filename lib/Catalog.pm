package Catalog;
use strict;
use warnings;
use utf8;
use parent 'Exporter';

our @EXPORT = qw(categories category_ids normalize_category items_by_category);

my @CATEGORIES = (
    { id => 'knowledge', label => 'Knowledge' },
    { id => 'official',  label => 'Official' },
    { id => 'security',  label => 'Security' },
);

sub categories {
    return map { +{%$_} } @CATEGORIES;
}

sub category_ids {
    return map { $_->{id} } @CATEGORIES;
}

sub normalize_category {
    my ($category) = @_;
    return undef unless defined $category;
    $category = lc $category;
    $category =~ s/^\s+|\s+$//g;

    my %known = map { $_ => 1 } category_ids();
    return $known{$category} ? $category : undef;
}

sub items_by_category {
    my ($items, $sorter) = @_;
    my @groups;
    for my $cat (categories()) {
        my @cat_items = grep { ($_->{category} || 'knowledge') eq $cat->{id} } @$items;
        @cat_items = sort { $sorter->($a, $b) } @cat_items if $sorter;
        push @groups, { %$cat, items => \@cat_items };
    }
    return @groups;
}

1;
