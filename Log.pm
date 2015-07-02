package Note::Log;
use strict;
use warnings;

use Data::Dumper;
use Time::HiRes 'gettimeofday', 'tv_interval';
use Scalar::Util 'blessed';
use RDF::Trine;
use RDF::Trine::Serializer::Turtle;

use vars qw($start $timer);

BEGIN:
{
	our $timer = [gettimeofday()];
	our $start = [gettimeofday()];
}

sub main::log
{
	print STDERR Note::Log::log_text(@_);
}

sub main::_log
{
	print STDERR Note::Log::log_text(@_);
}

sub main::errorlog
{
	print STDERR Note::Log::log_text(@_);
}

sub main::_errorlog
{
	print STDERR Note::Log::log_text(@_);
}

sub errorlog
{
	print STDERR log_text(@_);
}

sub _errorlog
{
	print STDERR log_text(@_);
}

sub log
{
	print STDERR log_text(@_);
}

sub _log
{
	print STDERR log_text(@_);
}

# static method for logging
sub log_text
{
	my (@data) = @_;
	my $log = '';
	foreach my $i (@data)
	{
		if (ref($i))
		{
			if (blessed($i) && $i->isa('RDF::Trine::Model'))
			{
				my $ser = RDF::Trine::Serializer::Turtle->new();
				print $ser->serialize_model_to_string($i);
			}
			else
			{
				$log .= Dumper($i);
			}
		}
		elsif (defined $i)
		{
			$i =~ s/\n$//;
			$log .= "$i\n";
		}
		else
		{
			$log .= "\n";
		}
	}
	return $log;
}

# time logging

sub main::timelog
{
	print STDERR Note::Log::log_time(@_);
}

sub log_time
{
	my ($label) = shift;
	my $total = tv_interval($start);
	my $tm = tv_interval($timer);
	$timer = [gettimeofday()];
	return log_text("$tm Elasped - $total Total: ". $label);
}

1;

