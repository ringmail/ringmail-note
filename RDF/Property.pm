package Note::RDF::Property;
use strict;
use warnings;
no warnings 'uninitialized';

use vars qw();

use Moose;
use Data::Dumper;
use RDF::Trine ('iri', 'statement', 'literal', 'blank');
use RDF::Trine::Node;

use Note::Param;
use Note::RDF::Sparql;
use Note::RDF::NS 'ns_iri';

# instance data
has 'id' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Node',
	'required' => 1,
);

has 'rdf' => (
	'is' => 'rw',
	'isa' => 'Note::RDF::Sparql',
	'required' => 1,
);

# static method
sub create
{
	my (undef, $param) = get_param(undef, @_);
	my $id = $param->{'id'};
	unless (defined($id))
	{
		$id = blank();
	}
	my $rdf = $param->{'rdf'};
	# TODO: validate rdf
	my $item = new Note::RDF::Property(
		'rdf' => $rdf,
		'id' => $id,
	);
	$rdf->add_statement($id, ns_iri('rdf', 'type'), ns_iri('rdf', 'Property'));
	return $item;
}

sub get_domain
{
	my ($obj, $param) = get_param(@_);
	my $prop = $param->{'id'};
	$prop ||= $obj->id();
	my $gdb = $obj->rdf();
	my $attr = $gdb->build_sparql(
		'select' => ['?inst'],
		'where' => [
			[$prop, ns_iri('rdfs', 'domain'), '?inst'],
		],
	);
	my @prop = ();
	while (my $i = $attr->next())
	{
		push @prop, $i->{'inst'};
	}
	return \@prop;
}

sub get_range
{
	my ($obj, $param) = get_param(@_);
	my $prop = $param->{'id'};
	$prop ||= $obj->id();
	my $gdb = $obj->rdf();
	my $attr = $gdb->build_sparql(
		'select' => ['?inst'],
		'where' => [
			[$prop, ns_iri('rdfs', 'range'), '?inst'],
		],
	);
	my @prop = ();
	while (my $i = $attr->next())
	{
		push @prop, $i->{'inst'};
	}
	return \@prop;
}

sub add_domain
{
	my ($obj, $param) = get_param(@_);
	my $id = $obj->id();
	my $rdf = $obj->rdf();
	my $class = $param->{'class'};
	$rdf->add_statement($id, ns_iri('rdfs', 'domain'), $class);
}

sub add_range
{
	my ($obj, $param) = get_param(@_);
	my $id = $obj->id();
	my $rdf = $obj->rdf();
	my $class = $param->{'class'};
	$rdf->add_statement($id, ns_iri('rdfs', 'range'), $class);
}

1;

