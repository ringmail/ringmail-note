package Note::Data::Model;
use strict;
use warnings;

use Moose;
use RDF::Trine;
use Params::Validate;

use Note::Param;
use Note::Data::Base;
use Note::Data::Field;

use base 'Note::Data::Base';

has 'fields' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'default' => sub {
		return {},
	},
);

1;

