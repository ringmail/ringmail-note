package Note::SKOS;
use strict;
use warnings;
no warnings qw(uninitialized);

use Moose;
use RDF::Trine ('iri', 'statement', 'literal', 'blank');

use Note::RDF::Sparql;
use Note::RDF::NS ('ns_iri');
use Note::Param;
use Note::SKOS::Concept;

has 'rdf' => (
	'is' => 'rw',
	'isa' => 'Note::RDF::Sparql',
	'required' => 1,
);

has 'id' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Node',
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
	$rdf->add_statement($id, ns_iri('rdf', 'type'), ns_iri('skos', 'ConceptScheme'));
	if (defined $param->{'top_concept'})
	{
		list_apply($param->{'top_concept'}, sub {
			my $c = shift;
			$rdf->add_statement($id, ns_iri('skos', 'hasTopConcept'), $c);
		});
	}
	return new Note::SKOS(
		'rdf' => $rdf,
		'id' => $id,
	);
}

sub get_top_concepts
{
	my ($obj, $param) = get_param(@_);
	my $rdf = $obj->rdf();
	my $iter = $rdf->get_statements($obj->id(), ns_iri('skos', 'hasTopConcept'), undef);
	my @result = ();
	while (my $c = $iter->next())
	{
		push @result, $c->[2];
	}
	return \@result;
}

sub set_top_concept
{
	my ($obj, $param) = get_param(@_);
	unless (defined($param->{'concept'}) && $param->{'concept'}->isa('RDF::Trine::Node'))
	{
		die('Invalid concept');
	}
	my $rdf = $obj->rdf();
### Do not delete
#	my $iter = $rdf->get_statements($obj->id(), ns_iri('skos', 'hasTopConcept'), undef);
#	while (my $i = $iter->next())
#	{
#		$rdf->delete('statement' => statement(@$i));
#	}
	$rdf->add_statement($obj->id(), ns_iri('skos', 'hasTopConcept'), $param->{'concept'});
	return undef;
}

sub add_concept
{
	my ($obj, $param) = get_param(@_);
	my $concept = Note::SKOS::Concept::create(
		%$param,
		'scheme' => $obj,
	);
	return $concept;
}

1;

