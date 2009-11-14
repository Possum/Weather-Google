#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 7;
use Test::Warn;

use Weather::Google;

my $gw = new Weather::Google();

# 1
is($gw->language(), undef, "default language: undef");

# 2
$gw->language("de");
is($gw->language(), "de", "set language via language(): 'de'");

$gw = new Weather::Google("Herne, Germany", {language => "de"});

# 3
is($gw->language(), "de", "set language via new(): 'de'");

# 4
warning_like {
    $gw = new Weather::Google( "Herne, Germany",
        { language => "unsupported" } );
} qr/^"unsupported" is not a supported ISO language code\./;

# 5
is($gw->language(), undef, "set unsupported language via new(): not set");

# 6
warning_like {
    $gw->language("unsupported");
} qr/^"unsupported" is not a supported ISO language code\./;

# 7
is($gw->language(), undef, "set unsupported language via language(): not set");
