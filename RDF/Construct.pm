package Note::RDF::Construct;
use strict;
use warnings;
no warnings qw(uninitialized);

use Moose;
use RDF::Trine ('iri', 'statement', 'literal');
use RDF::Trine::Store;
use Scalar::Util ('reftype', 'blessed');

use Note::RDF::Sparql;
use Note::RDF::NS ('ns_iri');
use Note::Param;

has 'store' => (
	'is' => 'rw',
	'isa' => 'Note::RDF::Sparql',
);

# params:
#  graph
sub get_classes
{
	my ($obj, $param) = get_param(@_);
	my $sto = $obj->store();
	my $itr = $sto->build_sparql(
		'select' => ['distinct ?class'],
		'from' => $param->{'graph'},
		'where' => [
			['?inst', ns_iri('rdf', 'type'), '?class'],
		],
		'order' => 'asc(?class)',
	);
	my @cls = ();
	while (my $i = $itr->next())
	{
		push @cls, $i->{'class'};
	}
	return \@cls;
}

# params:
#  class
#  graph
#  base (optional)
sub get_class_properties
{
	my ($obj, $param) = get_param(@_);
	my $sto = $obj->store();
	my $itr;
	unless (blessed($param->{'class'}) && $param->{'class'}->isa('RDF::Trine::Node::Resource'))
	{
		die('Invalid class parameter');
	}
	if ($param->{'base'})
	{
		$itr = $sto->build_sparql(
			'select' => ['distinct ?prop'],
			'from' => $param->{'graph'},
			'where' => [
				['?inst', ns_iri('rdf', 'type'), '?class'],
				['?inst', '?prop', '?value'],
			],
			'filter' => [
				{
					'?class' => $param->{'class'},
				},
				'and',
				"regex(str(?prop), \"^$param->{'base'}\")",
			],
			'order' => 'asc(?prop)',
		);
	}
	else
	{
		$itr = $sto->build_sparql(
			'select' => ['distinct ?prop'],
			'from' => $param->{'graph'},
			'where' => [
				['?inst', ns_iri('rdf', 'type'), '?class'],
				['?inst', '?prop', '?value'],
			],
			'filter' => {
				'?class' => $param->{'class'},
			},
			'order' => 'asc(?prop)',
		);
	}
	my @prop = ();
	while (my $i = $itr->next())
	{
		push @prop, $i->{'prop'};
	}
	return \@prop;
}

# params:
#  property
#  graph
#  base (optional)
# description:
#  get the rdf:type(s) of values of this property
sub get_property_classes
{
	my ($obj, $param) = get_param(@_);
	my $sto = $obj->store();
	my $itr;
	unless (blessed($param->{'property'}) && $param->{'property'}->isa('RDF::Trine::Node::Resource'))
	{
		die('Invalid property parameter');
	}
	if ($param->{'base'})
	{
		$itr = $sto->build_sparql(
			'select' => ['distinct ?class'],
			'from' => $param->{'graph'},
			'where' => [
				['?inst', '?prop', '?value'],
				['?value', ns_iri('rdf', 'type'), '?class'],
			],
			'filter' => [
				{
					'?prop' => $param->{'property'},
				},
				'and',
				"regex(str(?class), \"^$param->{'base'}\")",
			],
			'order' => 'asc(?class)',
		);
	}
	else
	{
		$itr = $sto->build_sparql(
			'select' => ['distinct ?class'],
			'from' => $param->{'graph'},
			'where' => [
				['?inst', '?prop', '?value'],
				['?value', ns_iri('rdf', 'type'), '?class'],
			],
			'filter' => {
				'?prop' => $param->{'property'},
			},
			'order' => 'asc(?class)',
		);
	}
	my @cls = ();
	while (my $i = $itr->next())
	{
		push @cls, $i->{'class'};
	}
	return \@cls;
}

# params:
#  property
#  graph
#  base (optional)
# description:
#  get the datatypes of values of this property
sub get_property_datatypes
{
	my ($obj, $param) = get_param(@_);
	my $sto = $obj->store();
	unless (blessed($param->{'property'}) && $param->{'property'}->isa('RDF::Trine::Node::Resource'))
	{
		die('Invalid property parameter');
	}
	my $itr = $sto->build_sparql(
		'select' => ['distinct (datatype(?value) as ?dtype)'],
		'from' => $param->{'graph'},
		'where' => [
			['?inst', '?prop', '?value'],
		],
		'filter' => {
			'?prop' => $param->{'property'},
		},
		'order' => 'asc(?dtype)',
	);
	my @data = ();
	while (my $i = $itr->next())
	{
		next unless (defined $i->{'dtype'});
		push @data, iri($i->{'dtype'}->value());
	}
	return \@data;
}

# params:
#  class - iri
#  properties: [{
#   property - iri
#   range
sub make_schema
{
	my ($obj, $param) = get_param(@_);
	my $cls = $param->{'class'};
	unless ($cls->isa('RDF::Trine::Node::Resource'))
	{
		die('Invalid class for make schema');
	}
	# add class instance
	$obj->make_schema_class(
		'class' => $cls,
	);
	# create properties
	my $props = $param->{'properties'} || [];
	foreach my $p (@$props)
	{
		$obj->make_schema_property(
			'property' => $p->{'property'},
			'domain' => $cls,
			'range' => $p->{'range'},
		);
	}
}

sub make_schema_class
{
	my ($obj, $param) = get_param(@_);
	my $cls = $param->{'class'};
	my $sto = $obj->store();
	$sto->add_statement($cls, ns_iri('rdf', 'type'), ns_iri('rdfs', 'Class'));
}

sub make_schema_property
{
	my ($obj, $param) = get_param(@_);
	my $prop = $param->{'property'};
	my $sto = $obj->store();
	$sto->add_statement($prop, ns_iri('rdf', 'type'), ns_iri('rdfs', 'Property'));
	foreach my $k (qw/domain range/)
	{
		if (defined($param->{$k}))
		{
			if (blessed($param->{$k}) && $param->{$k}->isa('RDF::Trine::Node::Resource'))
			{
				$sto->add_statement($prop, ns_iri('rdfs', $k), $param->{$k});
			}
			elsif (reftype($param->{$k}) eq 'ARRAY') # keep in mind that RDF::Trine::Node::Resource objects are blessed arrayrefs
			{
				foreach my $rec (@{$param->{$k}})
				{
					#::log("$k: ", $rec);
					if (blessed($rec) && $rec->isa('RDF::Trine::Node::Resource'))
					{
						$sto->add_statement($prop, ns_iri('rdfs', $k), $rec);
					}
					else
					{
						die('Invalid property '. $k);
					}
				}
			}
			else
			{
				die('Invalid property '. $k);
			}
		}
	}
}

1;

