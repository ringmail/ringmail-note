package Note::Data::Type;
use strict;
use warnings;

use Moose;
use RDF::Trine;
use Params::Validate;

use Note::Param;
use Note::Data::Instance;
use Note::Data::Type;

use base 'Note::Data::Instance';

# validate an input field
sub validate_field
{
	my ($obj, $param) = get_param(@_);
}

1;

