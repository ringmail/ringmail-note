package Note::RDF::Class;
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
use Note::RDF::Property;

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
	my $item = new Note::RDF::Class(
		'rdf' => $rdf,
		'id' => $id,
	);
	$rdf->add_statement($id, ns_iri('rdf', 'type'), ns_iri('rdfs', 'Class'));
	return $item;
}

sub get_super
{
	my ($obj, $param) = get_param(@_);
	my $class = $param->{'id'};
	$class ||= $obj->id();
	my $rdf = $obj->rdf();
	my $sc = $rdf->build_sparql(
		'select' => ['distinct ?inst'],
		'where' => [
			['?inst', ns_iri('rdf', 'type'), ns_iri('rdfs', 'Class')],
			[$class, ns_iri('rdfs', 'subClassOf'), '?inst'],
		],
	);
	my @sup = ();
	while (my $i = $sc->next())
	{
		push @sup, $i->{'inst'};
	}
	return \@sup;
}

sub get_super_all
{
	my ($obj, $param) = get_param(@_);
	my $class = $param->{'id'};
	$class ||= $obj->id();
	my @sup = ();
	my %seen = ();
	my $iter;
	$iter = sub {
		my ($cl) = @_;
		my $lookup = $obj->get_super('id' => $cl);
		foreach my $n (@$lookup)
		{
			unless ($seen{$n->uri_value()}++)
			{
				push @sup, $n;
				$iter->($n);
			}
		}
	};
	$iter->($class);
	return \@sup;
}

sub get_subclass
{
	my ($obj, $param) = get_param(@_);
	my $class = $param->{'id'};
	$class ||= $obj->id();
	my $rdf = $obj->rdf();
	my $sc = $rdf->build_sparql(
		'select' => ['distinct ?inst'],
		'where' => [
			['?inst', ns_iri('rdf', 'type'), ns_iri('rdfs', 'Class')],
			['?inst', ns_iri('rdfs', 'subClassOf'), $class],
		],
	);
	my @sub = ();
	while (my $i = $sc->next())
	{
		push @sub, $i->{'inst'};
	}
	return \@sub;
}

sub get_properties
{
	my ($obj, $param) = get_param(@_);
	my $class = $param->{'id'};
	$class ||= $obj->id();
	my $rdf = $obj->rdf();
	my $attr = $rdf->build_sparql(
		'select' => ['distinct ?inst'],
		'where' => [
			['?inst', ns_iri('rdf', 'type'), ns_iri('rdf', 'Property')],
			['?inst', ns_iri('rdfs', 'domain'), $class],
		],
	);
	my @prop = ();
	while (my $i = $attr->next())
	{
		if ($param->{'uri_only'})
		{
			push @prop, $i->{'inst'};
		}
		else # return Property objects unless 'uri_only' is specified
		{
			push @prop, new Note::RDF::Property(
				'id' => $i->{'inst'},
				'rdf' => $rdf,
			);
		}
	}
	return \@prop;
}

sub get_properties_all
{
	my ($obj, $param) = get_param(@_);
	my $class = $param->{'id'};
	$class ||= $obj->id();
	my $supercl = $obj->get_super_all('id' => $class);
	my $props = $obj->get_properties('id' => $class);
	my %seen = (map {$_->uri_value() => 1} @$props);
	if ($param->{'show_class'})
	{
		$props = [map {
			[$class, $_],
		} @$props];
	}
	foreach my $cl (@$supercl)
	{
		my $more = $obj->get_properties(
			'class' => $cl,
			'uri_only' => $param->{'uri_only'},
		);
		foreach my $m (@$more)
		{
			unless ($seen{$m->uri_value()}++)
			{
				if ($param->{'show_class'})
				{
					push @$props, [$cl, $m];
				}
				else
				{
					push @$props, $m;
				}
			}
		}
	}
	return $props;
}

sub add_property
{
	my ($obj, $param) = get_param(@_);
	my $prop = Note::RDF::Property::create({
		'rdf' => $obj->rdf(),
		'id' => $param->{'id'},
	});
	$prop->add_domain(
		'class' => $obj->id(),
	);
	return $prop;
}

1;

