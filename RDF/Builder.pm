package Note::RDF::Builder;
use strict;
use warnings;
no warnings qw(uninitialized);

use Moose;
use RDF::Trine ('iri', 'statement', 'literal');
use RDF::Trine::Store;
use Note::Param;

has 'schema' => (
	'is' => 'rw',
	'isa' => 'Note::Schema',
);

has 'model' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Model',
);

sub param
{
	shift(@_);
	return Note::Param::get_param(@_);
}

sub build_graph
{
	my ($obj, $param) = $_[0]->param(@_);
	my $sch = $obj->schema();
	my $ks = $sch->keys();
	my $store = RDF::Trine::Store->new_with_config({'storetype' => 'Memory'});
	my $model = RDF::Trine::Model->new($store);
	$obj->model($model);
	foreach my $k (@$ks)
	{
		my $fld = $sch->field($k);
		$obj->build_field(
			'key' => $k,
			'field' => $fld,
		);
	}
}

sub build_field
{
	my ($obj, $param) = $_[0]->param(@_);
	my $k = $param->{'key'};
	my $fld = $param->{'field'};
	my $attruri = $fld->get_rdf_property();
}

1;

