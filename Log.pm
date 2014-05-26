package Note::Log;
use strict;
use warnings;

use Data::Dumper;

sub main::_log
{
	print STDERR Note::Log::log_text(@_);
}

sub main::_errorlog
{
	print STDERR Note::Log::log_text(@_);
}

sub _errorlog
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
			$log .= Dumper($i);
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

1;

