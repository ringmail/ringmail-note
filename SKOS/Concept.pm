package Note::SKOS::Concept;
use strict;
use warnings;
no warnings qw(uninitialized);

use Moose;
use RDF::Trine ('iri', 'statement', 'literal', 'blank');

use Note::RDF::Sparql;
use Note::RDF::NS ('ns_iri');
use Note::Param;

has 'id' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Node',
);

has 'scheme' => (
    'is' => 'rw',
    'isa' => 'Note::SKOS',
);

sub create
{
    my (undef, $param) = get_param(undef, @_);
    my $id = $param->{'id'};
    unless (defined($id))
    {
        $id = blank();
    }
    my $rdf = $param->{'scheme'}->rdf();
    $rdf->add_statement($id, ns_iri('rdf', 'type'), ns_iri('skos', 'Concept'));
    if (defined $param->{'broader'}) # no list_apply used because with NOTE there should only be one "broader" parent node
    {
        my $r = $param->{'broader'};
        if (blessed($r) && $r->isa('RDF::Trine::Node'))
        {
            $rdf->add_statement($id, ns_iri('skos', 'broader'), $r);
        }
        else
        {
            die('Invalid rdf node');
        }
    }
    else # if no "broader" parent, then must be a top concept
    {
        $param->{'scheme'}->set_top_concept(
            'concept' => $id,
        );
    }
    return new Note::SKOS::Concept(
		'scheme' => $param->{'scheme'},
		'id' => $id,
	);
}

# get broader skos parent node
sub broader
{
    my ($obj, $param) = @_;
    my $rdf = $obj->scheme()->rdf();
    my $iter = $rdf->get_statements($obj->id(), ns_iri('skos', 'broader'), undef);
    if (my $i = $iter->next())
    {
        return $i->[2];
    }
    return undef;
}

# get narrower skos child nodes
sub narrower
{
    my ($obj, $param) = @_;
    my $rdf = $obj->scheme()->rdf();
    my $iter = $rdf->get_statements(undef, ns_iri('skos', 'broader'), $obj->id());
    my @result;
    if (my $i = $iter->next())
    {
        push @result, $i->[0];
    }
    return \@result;
}

1;

