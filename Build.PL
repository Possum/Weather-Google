#!/usr/bin/perl

use Module::Build;
use strict;
use warnings;

my $build = Module::Build->new (
	perl => 5.006,
	module_name => 'Weather::Google',
	license => 'perl',
	requires => {
		'LWP::Simple'  => 0,
		'XML::Simple'  => 0,
		'Test::More'   => 0,
		'Test::Simple' => 0,
		'Test::Pod'    => 0,
	},
);
$build->create_build_script;
