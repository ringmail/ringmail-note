package Note::Locale;
use strict;
use warnings;
no warnings qw(uninitialized);

BEGIN: {
	use base 'Exporter';
	use vars qw(@EXPORT @EXPORT_OK %states);
	@EXPORT_OK = qw(us_states us_state_name);
	use Geography::States;
	our %states = ();
};

END: {
	my $usa = new Geography::States('USA');
	foreach ($usa->state())
	{
		next if ($_->[0] =~ /GU|MH|MP|FM|AS|VI|PW|PR/);
		$states{$_->[0]} = $_->[1];
	}
};

sub us_states
{
	return [sort keys %states];
}

sub us_state_name
{
	my ($st) = @_;
	return $states{$st};
}

1;

