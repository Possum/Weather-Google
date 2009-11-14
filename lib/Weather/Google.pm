package Weather::Google;

use strict;
use warnings;
use LWP::Simple qw/get/;
use XML::Simple;

our $ENCODE;
$ENCODE = 1 if eval { require Encode };

our $VERSION = 0.04;
our $AUTOLOAD;
use constant GAPI => 'http://www.google.com/ig/api?weather=';

sub new {
	my ( $class, $area, $opt ) = @_;
    my $self = {};
	bless ($self,$class);

	$self->{xs} = XML::Simple->new;

	$self->language($opt->{language}) if defined $opt->{language};

	return $self unless $area;

	if ( $area =~ /^\d{5}?$/ ) {
		$self->zip($area);
		return $self;
	}

	$self->city($area);
	return $self;
}

sub _location_url {
    my ( $self, $loc ) = @_;
    # TODO This should be modified to support, i.e., a hash of parameters.
    my $url = GAPI . $loc;
    my $lang = $self->language;
    $url .= "&hl=$lang" if $lang;
    return $url;
}

sub zip {
	my $self = shift;
	my $zip = shift;
	unless ($zip =~ /\d{5}?$/) {
		$self->err("Not a zip code");
		return;
	}

	my $xml = get($self->_location_url($zip));
	$xml = Encode::decode_utf8($xml,$Encode::FB_DEFAULT) if $ENCODE;
	my $w = $self->{xs}->xml_in($xml) or return;
#	my $w = $self->{xs}->parse($xml) or return;

	$self->_parse($w);
	return 1;
}

sub city {
	my $self = shift;
	my $loc = shift;

	# Encode the location for URL
	$loc =~ s/([^\w()’*~!.-])/sprintf '%%%02x', ord $1/eg;
	my $xml = get($self->_location_url($loc));
	if ( $ENCODE ) {
		$xml = Encode::decode_utf8($xml,$Encode::FB_DEFAULT);
	} else {
		$xml =~ s/[01[:^ascii:]%]//g;
	}
	my $w = $self->{xs}->xml_in($xml) or return;

	$self->_parse($w);
	return 1;
}

sub language {
	my $self = shift;

	return $self->{lang} unless @_;
    my $lang = shift;

	# List of supported languages according to
	# http://toolbar.google.com/buttons/apis/howto_guide.html#multiplelanguages
	my %languages = map { $_ => 1 } qw/
	    en da de es fi fr it ja ko nl no pt-BR ru sv zh-CN zh-TW
	/;

	unless (defined $languages{$lang})
	{
	    warn qq|"$lang" is not a supported ISO language code.\n|;
	    return $self->{lang};
	}

	$self->{lang} = $lang;
}

sub current_conditions {
	my $self = shift;
	return $self->{current} unless @_;
	my @conds = @_;
	my @out;
	foreach my $cond (@conds) {
		if (defined($self->{current}->{$cond})) {
			push (@out, $self->{current}->{$cond});
		} else {
			$self->err("No current condition $cond");
			push (@out, undef);
		}
	}
	return $out[0] unless $#out;
	return @out;
}

sub forecast_conditions {
	my $self = shift;
	return $self->{forecast} unless @_;
	my $day = shift;

	$day = 0 if $day =~ /today/i;
	$day = 1 if $day =~ /tomorrow/i;
	unless ($day =~ /^\d+$/) {
		# Only take the first three letters
		if ($day =~ /^(\w{3})\w*day$/i) {
			$day = $1;
		}
		# Check to see if we have a day that matches 
		for ( my $i = 0; $i <= $#{ $self->{forecast} }; $i++ ) {
			if ($self->{forecast}->[$i]->{day_of_week} =~ /^$day/i) {
				$day = $i;
				last;
			}
		}
		unless ($day =~ /^\d+$/) {
			# Give up...
			$self->err("Can't find info for the day $day");
			return;
		}
	}
	return $self->{forecast}->[$day] unless @_;
	my @conds = @_;
	my @out;
	foreach my $cond (@conds) {
		if (defined($self->{forecast}->[$day]->{$cond})) {
			push (@out, $self->{forecast}->[$day]->{$cond});
		} else {
			$self->err("No forecast condition $cond for day $day");
			push (@out, undef);
		}
	}
	return $out[0] unless $#out;
	return @out;
}

sub forecast_information {
	my $self = shift;
	return $self->{info} unless @_;
	my @conds = @_;

	my @out;
	foreach my $cond (@conds) {
		if (defined($self->{info}->{$cond})) {
			push (@out, $self->{info}->{$cond});
		} else {
			$self->err("No info condition $cond");
			push (@out, undef);
		}
	}
	return $out[0] unless $#out;
	return @out;
}

sub err {
	my $self = shift;
	$self->{ERR} = shift if @_;
	return $self->{ERR};
}

sub _parse {
	my $self = shift;
	my $w = shift;

	$self->{version} = $w->{version};
	$w = $w->{weather};

	$self->{current} = $w->{current_conditions};
	$self->{forecast} = $w->{forecast_conditions};
	$self->{info} = $w->{forecast_information};

	# Make these a bit more readable:
	foreach my $key ( keys ( %{ $self->{current} } ) ) {
		$self->{current}->{$key} = $self->{current}->{$key}->{data};
	}
	foreach my $key ( keys ( %{ $self->{info} } ) ) {
		$self->{info}->{$key} = $self->{info}->{$key}->{data};
	}
	foreach my $day ( @{ $self->{forecast} } ) {
		foreach my $key ( keys ( %{ $day } ) ) {
			$day->{$key} = $day->{$key}->{data};
		}
	}
}

sub DESTROY {
}

sub AUTOLOAD {
	my $self = shift;

	# Alias some things

	my $name = $AUTOLOAD;
	$name =~ s/.+:://;

	# This should prevent warnings of undefined @_
	@_ = () unless @_;

	return $self->current_conditions(@_) if $name eq 'current';
	return $self->forecast_conditions(@_) if $name eq 'forecast';
	return $self->forecast_information(@_) if $name eq 'info';

	# Day of week shortcut
	return $self->forecast_conditions($name,@_) if
		$name =~ /^(Today|Tomorrow)|((Mon|Tue|Wed|Thu|Fri|Sat|Sun)(\w*day)?)$/i;

	# Others are considered access methods to current_conditions
	return $self->current($name);
}

1;

__END__;

=head1 NAME

Weather::Google - Perl interface to Google's Weather API

=cut

=head1 VERSION

Version 0.03

=cut

=head1 SYNOPSIS

 use Weather::Google;

 # If you plan on using locations with non-ASCII characters
 use encoding 'utf8';

 my $gw;

 ## Initialize the module
 $gw = new Weather::Google(90210); # Zip code
 $gw = new Weather::Google('Beverly Hills, CA'); # City name
 $gw = new Weather::Google('Herne, Germany',{language => 'de'});

 # Or
 $gw = new Weather::Google;
 $gw->zip(90210); # Zip code
 $gw->city('Beverly Hills, CA'); # City name
 $gw->language('de'); # Localization

 ## Get some current information

 my @info;
 @info = $gw->current('temp_f','temp_c','humidity','wind_condition');

 # Or
 my $current = $gw->current;
 @info = ($current->{temp_f}, $current->{temp_c}, $current->{humidity});

 # Or
 @info = ($gw->temp_f, $gw->temp_c, $gw->humidity, $gw->wind_condition);

 ## Forecast
 
 print "Today's high: ", $gw->forecast(0,'high');
 print "Today's high: ", $gw->forecast('Today','high');
 print "Today's high: ", $gw->today('high');

 # Assuming Today is Monday:
 print "Tomorrow's high: ", $gw->forecast(1,'high');
 print "Tomorrow's high: ", $gw->forecast('Tue','high');
 print "Tomorrow's high: ", $gw->tue('high');
 
 ## Forecast information:
 print "Forecast for ". $gw->info('city'). "made at ".
 	$gw->info('current_date_time');

=cut

=head1 DESCRIPTION

Weather::Google provides a simple interface to Google's Weather API.

=cut

=head1 METHODS

=over

=cut

=item new

Initializes and returns a Weather::Google object.  Optionally takes a
Zip/postal code or city name as an argument, optionally followed by a hashref
of additional options:

=over

=item language

Have a look at the language() method's description below.

=back

=cut

=item zip

Sets the zip/postal code for the Weather::Google object.  Takes a 5 digit
integer as an argument.  Returns 1 on success.

=cut

=item city

Sets the city for the Weather::Google object.  Takes a string as an argument.
Returns 1 if successful.

=cut

=item language

Optionally takes an ISO language code as an argument (i.e. "en", "de") to set
the language that is passed to the weather query for proper localization.
(Default: "en")

Supported language codes: "en", "da", "de", "es", "fi", "fr", "it", "ja",
"ko", "nl", "no", "pt-BR", "ru", "sv", "zh-CN", "zh-TW"

Returns the currently set ISO language code.

=cut

=item current_conditions

Method to report on current weather conditions.  With no argument, this
returns a hash reference containing weather information.  Optionally takes an
array of conditions to fetch. 

Returns a scalar containing the requested information if only one argument is
passed, or an array of information if multiple arguments are passed.  The
information will be in the same order as requested; nonexistant information is
returned as undef.

 # Example 1:
 my $info = $gw->current_conditions;
 foreach my $condition ( keys ( %$info ) ) {
 	print "$condition: ", $info->{$condition}, "\n";
 }

 # Example 2:
 my @info = $gw->current_conditions('temp_f','temp_c');
 print "Temperature in F and C: @info";

 # Example 3:
 my $temp_f = $gw->current_conditions('temp_f');
 my $temp_c = $gw->current_conditions('temp_c');
 print "It is $temp_f F ($temp_c C) degrees\n";

=over

=item ARGUMENTS

The current_conditions() method will take any string as an argument, but will
return undefs if the information is not available.  It is generally safe to
use the following strings as arguments:

 icon
 temp_f
 temp_c
 wind_condition
 humidity
 condition

=back

See also the B<ALIASES> section for easier methods to access
current_conditions().

=cut

=item forecast_conditions

Method to report on weather conditions over the next few days.  With no
argument, this returns an array reference containing a hash reference
containing weather information for each day available.  Optionally takes a day
of the week (as a string containing the first three letters of the day) or an
array index number (where 0 is today, 1 is tomorrow, etc.) as the first
argument, and an array of conditions to fetch as subsequent arguments.. 

If a day is given, but no conditions are passed, this method will return a
hash reference containing conditions for that day.

If conditions are passed, this method returns a scalar containing the
requested information if only one condition is requested, or an array of
information if multiple conditions are requested.  The information will be in
the same order as requested; nonexistant information is returned as undef.

 # Example 1:
 my $days = $gw->forecast_conditions;
 foreach my $day (@$days) {
 	# See Example 2
 }

 # Example 2:
 my $today = $gw->forecast_conditions(0);
 print "High: ".$today->{high}."\n";
 
 # Example 3:
 my $tom_high = $gw->forecast_conditions(1,'high');
 my $tue_low = $gw->forecast_conditions('Tue','low);
 print "Tomorrow's high is $tom_high and Tuesday's low is $tue_low\n";

=over

=item ARGUMENTS

The forecast_conditions() method will take any string as an argument, but will
return undefs if the information is not available.It is generally safe to use
the following strings as arguments:

 icon
 high
 low
 day_of_week
 condition

=back

See also the B<ALIASES> section for easier methods to access
forecast_conditions().

=cut

=item forecast_information

Method to report various information about the forecast itself. With no
argument, this returns a hash reference containing various information.
Optionally takes an array of conditions to fetch. 

Returns a scalar containing the requested information if only one argument is
passed, or an array of information if multiple arguments are passed.  The
information will be in the same order as requested; nonexistant information is
returned as undef.

 # Example 1:
 my $info = $gw->forecast_information;
 print "Zip: ".$info->{postal_code}."\n";

 # Example 2:
 my $city = $gw->forecast_information('city');
 print "Forecast for $city:\n";

 # Example 3:
 my @info = $gw->forecast_information('city','postal_code');

=over

=item ARGUMENTS

The forecast_informatio() method will take any string as an argument, but will
return undefs if the information is not available.  It is generally safe to
use the following strings as arguments:

 forecast_date
 current_date_time
 city
 postal_code
 unit_system
 latitude_e6
 longitude_e6

Using B<latitude_e6> or B<longitude_e6> may return undef or strange values,
since Google doesn't normally set them.

=back

See also the B<ALIASES> section for easier methods to access
forecast_information().

=cut

=item err

This method returns the most recent error.

This is generally useful if you expect one of the other methods to return
something, but it returns undef instead.

=back

=cut

=head1 ALIASES

Using the methods defined in METHODS in a script can get annoying very
quickly.  Luckily, Weather::Google provides methods that can be used as
aliases for the defined methods.

=head2 SIMPLE ALIASES

The methods current(), forecast(), and info() can be used in place of
current_conditions(), forecast_conditions(), and forecast_information()
respectively.

=head2 DAY OF WEEK

The methods today(), tomorrow(), mon(), tue(), wed(), thu(), fri(), sat(), and
sun() can be used as alias to forecast_conditions($day), where $day is the
name of the method.

You can also use the full name (i.e., monday() or tuesday()) as opposed to the
first three letters.

=head2 CURRENT CONDITION

Any other method is used as an alias to current_conditions($method) where
$method is the name of the method.  This means, for example, you can use
temp_f() as an implied alias for current_conditions('temp_f'), and so on.

=head1 AUTHOR

Daniel LeWarne C<< <possum at cpan.org> >>

=head1 BUGS

Google's XML files occasionally sends invalid UTF-8.  Google::Weather can
generally compensate for this, bu if you would like to force Google::Weather to
strip utf8 characters instead of trying to re-encode them, you can say

 use Weather::Google;
 $Weather::Google::ENCODE=0;

to force non-ASCII characters to be stripped from the output.

Please report any bugs or feature requests to C<bug-weather-google at
rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Weather-Google>.  I will be
notified, and then you'll automatically be notified of progress on your bug as
I make changes.

=head1 COPYRIGHT

Copyright (C) 2008 Daniel "Possum" LeWarne.  All Rights Reserved.

This program is free software, you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

This (very briefly) discusses the Weather API

L<http://toolbar.google.com/buttons/apis/howto_guide.html>

