package Renderer;
use strict;
use warnings;
use utf8;
use parent 'Exporter';

use Digest::SHA qw(sha256_hex);
use Catalog;
use Util qw(html html_attr now_iso write_text normalize_color favicon_url);

our @EXPORT = qw(write_edition_html write_archive_html static_css);

sub write_edition_html {
    my ($path, $title, $cats_data, $base, $is_root) = @_;
    my $password_hash = $ENV{VIEW_PASSWORD} ? sha256_hex($ENV{VIEW_PASSWORD}) : '';
    my $gate_class = $password_hash ? 'locked' : '';
    my $gate = $password_hash ? password_gate($password_hash) : '';

    my $tabs_html = join "\n", map {
        my $n = scalar @{$_->{items}};
        my $active = $_->{id} eq 'knowledge' ? ' active' : '';
        qq{        <button class="tab-btn$active" data-tab="$_->{id}">@{[html($_->{label})]}<span class="cnt">$n</span></button>};
    } @$cats_data;

    my $panels_html = join "\n", map {
        my $active = $_->{id} eq 'knowledge' ? ' active' : '';
        my $items_html = @{$_->{items}}
            ? join("\n", map { render_item($_) } @{$_->{items}})
            : '<p class="empty">No new articles in this edition.</p>';
        qq{    <section class="tab-panel$active" id="tab-$_->{id}"><div class="feed">\n$items_html\n    </div></section>};
    } @$cats_data;

    my $total = 0; $total += scalar @{$_->{items}} for @$cats_data;

    my $brand_html = $is_root
        ? qq{<h1>Catch News</h1>}
        : qq{<a href="${base}archive.html" class="back-btn" aria-label="Archive">&#8592;</a>\n        <h1>@{[html($title)]}</h1>};

    my $extra_link = $is_root
        ? qq{<a href="${base}archive.html" class="sub-link">Archive &#8594;</a>}
        : qq{<a href="${base}index.html" class="sub-link">Latest &#8594;</a>};

    write_text($path, <<"HTML");
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex,nofollow,noarchive">
  <title>@{[html($is_root ? 'Catch News' : $title)]}</title>
  <link rel="stylesheet" href="${base}style.css">
</head>
<body class="$gate_class">
$gate
  <main id="content" class="wrap">
    <header>
      <div class="brand">
        $brand_html
      </div>
      <div class="header-right">
        $extra_link
        <div class="tabs">
$tabs_html
        </div>
      </div>
    </header>
    <p class="meta">Generated at @{[now_iso()]} / $total items</p>
$panels_html
  </main>
  <script>
    document.querySelectorAll('.tab-btn').forEach(b => {
      b.addEventListener('click', () => {
        document.querySelectorAll('.tab-btn, .tab-panel').forEach(el => el.classList.remove('active'));
        b.classList.add('active');
        document.getElementById('tab-' + b.dataset.tab).classList.add('active');
      });
    });
  </script>
</body>
</html>
HTML
}

sub render_item {
    my ($item) = @_;
    my $date = $item->{published_at} || $item->{fetched_at} || '';
    my $score = defined $item->{score} ? " ・ $item->{score} pts" : '';
    my $color = normalize_color($item->{source_color}) || '#475569';
    my $icon = $item->{source_icon} || favicon_url($item->{source_home} || $item->{url});
    my $source_mark = $icon
        ? qq{<img src="@{[html_attr($icon)]}" alt="" loading="lazy">}
        : '<span class="dot"></span>';
    return <<"HTML";
    <a href="@{[html_attr($item->{url})]}" class="item" style="--accent: @{[html_attr($color)]}" target="_blank" rel="noopener noreferrer">
      <div class="thumb"><div class="noimage"><span>@{[html($item->{title})]}</span></div></div>
      <div class="body">
        <div class="source"><span class="pill">$source_mark@{[html($item->{source} || '')]}</span><span class="date">@{[html($date)]}$score</span></div>
      </div>
    </a>
HTML
}

sub password_gate {
    my ($hash) = @_;
    return <<"HTML";
  <section id="gate">
    <h1>Catch News</h1>
    <input id="password" type="password" autocomplete="current-password" placeholder="Password">
    <button id="unlock" type="button">Open</button>
    <p id="error" class="error"></p>
  </section>
  <script>
    const expected = "$hash";
    const gate = document.getElementById("gate");
    const error = document.getElementById("error");
    const input = document.getElementById("password");
    async function sha256(text) {
      const bytes = new TextEncoder().encode(text);
      const hash = await crypto.subtle.digest("SHA-256", bytes);
      return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, "0")).join("");
    }
    async function unlock() {
      if (await sha256(input.value) === expected) {
        sessionStorage.setItem("catch_news_unlocked", "1");
        document.body.classList.remove("locked");
        gate.remove();
      } else {
        error.textContent = "Password is incorrect.";
      }
    }
    if (sessionStorage.getItem("catch_news_unlocked") === "1") {
      document.body.classList.remove("locked");
      gate.remove();
    }
    document.getElementById("unlock").addEventListener("click", unlock);
    input.addEventListener("keydown", event => { if (event.key === "Enter") unlock(); });
  </script>
HTML
}

sub write_archive_html {
    my ($path, $editions) = @_;
    my $password_hash = $ENV{VIEW_PASSWORD} ? sha256_hex($ENV{VIEW_PASSWORD}) : '';
    my $gate_class = $password_hash ? 'locked' : '';
    my $gate = $password_hash ? password_gate($password_hash) : '';

    my %seen_date;
    my @dates;
    for my $ed (sort { ($b->{slug} || '') cmp ($a->{slug} || '') } @$editions) {
        my $d = $ed->{date} || substr($ed->{slug} || '', 0, 8);
        push @dates, $d unless $seen_date{$d}++;
    }
    my %by_date;
    for my $ed (@$editions) {
        my $d = $ed->{date} || substr($ed->{slug} || '', 0, 8);
        push @{ $by_date{$d} }, $ed;
    }

    my $list_html = '';
    for my $date (@dates) {
        my @eds = sort { ($b->{slug} || '') cmp ($a->{slug} || '') } @{ $by_date{$date} || [] };
        (my $disp = $date) =~ s/^(\d{4})(\d{2})(\d{2})$/$1-$2-$3/;
        $list_html .= qq{<div class="date-group">\n<h2 class="date-heading">@{[html($disp)]}</h2>\n<div class="edition-list">\n};
        for my $ed (@eds) {
            my $slug   = $ed->{slug}  || '';
            my $title  = $ed->{title} || $slug;
            my $by_cat = $ed->{by_category} || {};
            my @badges;
            for my $cat (categories()) {
                my $n = $by_cat->{$cat->{id}} || 0;
                next unless $n;
                push @badges, qq{<span class="cat-badge">$cat->{label}<span class="cnt">$n</span></span>};
            }
            my $cats_html = @badges
                ? join('', @badges)
                : qq{<span class="no-items">no new items</span>};
            $list_html .= qq{<a href="./articles/$slug.html" class="edition-row"><span class="ed-title">@{[html($title)]}</span><div class="ed-cats">$cats_html</div></a>\n};
        }
        $list_html .= "</div>\n</div>\n";
    }
    $list_html ||= '<p class="empty">No editions yet.</p>';

    write_text($path, <<"HTML");
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex,nofollow,noarchive">
  <title>Catch News</title>
  <link rel="stylesheet" href="./style.css">
</head>
<body class="$gate_class">
$gate
  <main id="content" class="wrap">
    <header>
      <div class="brand">
        <h1>Archive</h1>
      </div>
      <a href="./index.html" class="sub-link">Latest &#8594;</a>
    </header>
    $list_html
  </main>
</body>
</html>
HTML
}

sub static_css {
    return <<'CSS';
:root {
  color-scheme: light dark;
  --bg: #f7f8fa; --panel: #ffffff; --ink: #15171a; --line: #e6e8ec;
  --muted: #6b7280; --soft: #f2f4f7; --header-bg: rgba(247,248,250,0.92);
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #101214; --panel: #181b20; --ink: #f4f7fb; --line: #2a3038; --muted: #9aa4b2; --soft: #20252d; --header-bg: rgba(16,18,20,0.9); }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.55; }
.wrap { max-width: 900px; margin: 0 auto; padding: 18px 14px 56px; }

header { position: sticky; top: 0; z-index: 999; display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 14px 0 16px; background: var(--header-bg); backdrop-filter: blur(14px); border-bottom: 1px solid var(--line); }
.brand { display: flex; align-items: center; gap: 10px; min-width: 0; }
h1 { font-size: 22px; margin: 0; letter-spacing: 0; }
.back-btn { display: grid; place-items: center; width: 34px; height: 34px; border: 1px solid var(--line); border-radius: 8px; color: inherit; text-decoration: none; background: var(--panel); font-size: 18px; flex-shrink: 0; }
.back-btn:hover { border-color: var(--ink); }
.header-right { display: flex; flex-direction: column; align-items: flex-end; gap: 7px; }
.sub-link { font-size: 13px; color: var(--muted); text-decoration: none; white-space: nowrap; }
.sub-link:hover { color: var(--ink); }
.tabs { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 6px; }
.tab-btn { display: inline-flex; align-items: center; gap: 5px; height: 34px; padding: 0 10px; border: 1px solid var(--line); border-radius: 8px; color: inherit; font-size: 13px; background: var(--panel); cursor: pointer; }
.tab-btn.active { border-color: #15171a; background: #15171a; color: #fff; }
.tab-btn .cnt { font-size: 11px; opacity: 0.7; }
.tab-panel { display: none; }
.tab-panel.active { display: block; }

.meta { color: var(--muted); font-size: 13px; margin: 16px 0; }
.feed { display: grid; gap: 14px; grid-template-columns: repeat(4, 1fr); }
.item { --accent: #475569; display: flex; flex-direction: column; overflow: hidden; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); box-shadow: 0 1px 2px rgba(15,23,42,0.04); text-decoration: none; color: inherit; }
.item:hover { border-color: color-mix(in srgb, var(--accent) 42%, var(--line)); }
.item:hover .noimage { background: color-mix(in srgb, var(--accent) 22%, var(--soft)); }
.item:visited .noimage { color: color-mix(in srgb, var(--accent) 60%, var(--soft)); background: color-mix(in srgb, var(--accent) 10%, var(--soft)); }
.thumb { height: 130px; background: var(--soft); border-bottom: 1px solid var(--line); flex-shrink: 0; overflow: hidden; }
.noimage { display: flex; align-items: center; justify-content: center; padding: 14px; height: 100%; background: color-mix(in srgb, var(--accent) 14%, var(--soft)); color: color-mix(in srgb, var(--accent) 80%, var(--ink)); font-size: 12px; font-weight: 600; line-height: 1.45; text-align: center; }
.noimage span { display: -webkit-box; -webkit-line-clamp: 5; -webkit-box-orient: vertical; overflow: hidden; }
.body { min-width: 0; padding: 10px 12px; }
.source { color: var(--muted); font-size: 11px; display: flex; flex-wrap: wrap; gap: 5px; align-items: center; }
.pill { display: inline-flex; align-items: center; gap: 4px; min-height: 20px; padding: 1px 6px; border-radius: 999px; background: color-mix(in srgb, var(--accent) 10%, var(--soft)); color: var(--accent); font-weight: 700; }
.pill img { width: 13px; height: 13px; border-radius: 3px; object-fit: contain; }
.dot { width: 7px; height: 7px; border-radius: 999px; background: var(--accent); }
.date { font-variant-numeric: tabular-nums; }

.date-group { margin-top: 32px; }
.date-heading { font-size: 13px; color: var(--muted); font-weight: 600; letter-spacing: 0.05em; text-transform: uppercase; margin: 0 0 10px; }
.edition-list { display: grid; gap: 8px; }
.edition-row { display: flex; align-items: center; gap: 16px; padding: 14px 16px; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); flex-wrap: wrap; text-decoration: none; color: inherit; }
.edition-row:hover { border-color: var(--ink); }
.ed-title { font-weight: 700; font-size: 14px; min-width: 72px; }
.ed-cats { display: flex; flex-wrap: wrap; gap: 6px; }
.cat-badge { display: inline-flex; align-items: center; gap: 4px; height: 26px; padding: 0 9px; border-radius: 6px; font-size: 12px; background: var(--soft); color: var(--muted); }
.cnt { font-size: 12px; margin-left: 2px; }
.no-items { color: var(--muted); font-size: 13px; }

.empty { color: var(--muted); text-align: center; padding: 60px 0; }
.locked #content { display: none; }
#gate { max-width: 360px; margin: 24vh auto 0; padding: 0 16px; }
#gate input, #gate button { width: 100%; font: inherit; padding: 10px 12px; margin-top: 10px; border: 1px solid var(--line); border-radius: 8px; }
#gate button { cursor: pointer; background: #111827; color: #fff; }
#gate .error { color: #c2410c; min-height: 1.5em; }

@media (max-width: 900px) {
  .feed { grid-template-columns: repeat(3, 1fr); }
}
@media (max-width: 640px) {
  .wrap { padding-inline: 10px; }
  header { align-items: flex-start; flex-direction: column; gap: 10px; padding: 12px 0 14px; }
  .brand { width: 100%; }
  .brand h1 { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .header-right { width: 100%; flex-direction: column; align-items: stretch; gap: 8px; }
  .header-right .sub-link { align-self: flex-end; }
  .tabs { justify-content: stretch; flex-wrap: nowrap; width: 100%; }
  .tab-btn { flex: 1 1 0; justify-content: center; min-width: 0; padding: 0 6px; font-size: 12px; }
  .feed { grid-template-columns: repeat(2, 1fr); gap: 10px; }
  h1 { font-size: 18px; }
  .edition-row { gap: 10px; }
}
CSS
}

1;
