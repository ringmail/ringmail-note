package Note::Data::Field;
use strict;
use warnings;

use Moose;
use RDF::Trine;
use Params::Validate;

use Note::Param;
use Note::Data::Base;
use Note::Data::Type;

use base 'Note::Data::Base';

has 'key' => (
	'is' => 'rw',
	'isa' => 'Str',
	'required' => 1,
);

has 'type' => (
	'is' => 'rw',
	'isa' => 'Note::Data::Type',
	'required' => 1,
);


has 'label' => (
	'is' => 'rw',
	'isa' => 'Str',
	'lazy' => 1,
	'default' => sub {
		my $obj = $_[0];
		return $obj->key();
	},
);

has 'description' => (
	'is' => 'rw',
	'isa' => 'Str',
);

has 'model' => (
	'is' => 'rw',
	'isa' => 'Note::Data::Model',
	'weak_ref' => 1,
	'required' => 1,
);

1;

