package Note::Data::Instance;
use strict;
use warnings;

use RDF::Trine;
use Moose;

has 'id' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Node',
	'lazy' => 1,
	'builder' => '_blank_node',
);

sub _blank_node
{
	return new RDF::Trine::Node::Blank();
}

1;

