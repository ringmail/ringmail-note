package Note::RDF::Field_map;
use strict;
use warnings;

use vars qw();

use Moose;
use Data::Dumper;
use RDF::Trine ('iri', 'statement', 'literal');
use Note::Param;
use Note::RDF::NS ('ns_iri');
use Scalar::Util ('blessed', 'reftype');

no warnings 'uninitialized';

has 'model' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Model',
	'required' => 1,
);

has 'map_iri' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Node::Resource',
	'required' => 1,
);

has 'map_data' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'lazy' => 1,
	'default' => sub { return {}; },
);

has 'map_inverse' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'lazy' => 1,
	'default' => sub { return {}; },
);

sub BUILD
{
	my ($obj, $param) = get_param(@_);
	my $base = 'http://stg.atellix.com/';
	my $mapiri = $obj->map_iri();
	my $model = $obj->model();
	my $mprop = iri("${base}map_item/item_map");
	my $mapitems = $model->get_statements(undef, $mprop, $mapiri);
	my $data = $obj->map_data();
	my $invdata = $obj->map_inverse();
	while (my $st = $mapitems->next())
	{
		my $item = $st->subject();
		my $k = $model->get_statements($item, iri("${base}map_item/item_key"), undef)->next()->object()->literal_value();
		my $v = $model->get_statements($item, iri("${base}map_item/item_property"), undef)->next()->object()->uri_value();
		if (exists $data->{$k})
		{
			die(qq|Duplicate map item key: "$k"|);
		}
		$data->{$k} = $v;
		$invdata->{$v} = $k;
	}
}

sub build_instance
{
	my ($obj, $param) = get_param(@_);
	my $subject = $param->{'iri'};
	if (! defined($subject) && defined($param->{'uri'}))
	{
		$subject = iri($param->{'uri'});
	}
	my $data = $param->{'data'};
	unless (blessed($subject) && $subject->isa('RDF::Trine::Node::Resource'))
	{
		die('Invalid instance subject');
	}
	unless (reftype($data) eq 'HASH')
	{
		die('Invalid instance data');
	}
	my $mapdata = $obj->map_data();
	my $model;
	if (exists $param->{'model'})
	{
		$model = $param->{'model'};
		unless (blessed($model) && $model->isa('RDF::Trine::Model'))
		{
			die('Invalid instance model');
		}
	}
	else
	{
		$model = new RDF::Trine::Model();
	}
	foreach my $k (sort keys %$data)
	{
		unless (exists $mapdata->{$k})
		{
			die(qq|Invalid map key: "$k"|);
		}
		my $irik = iri($mapdata->{$k});
		my $v = $data->{$k};
		if (reftype($v) eq 'ARRAY' && ! (blessed($v) && $v->isa('RDF::Trine::Node')))
		{
			foreach my $iv (@$v)
			{
				$obj->_instance_field($model, $subject, $irik, $iv);
			}
		}
		else
		{
			$obj->_instance_field($model, $subject, $irik, $v);
		}
	}
	return $model;
}

sub _instance_field
{
	my ($obj, $model, $subject, $irik, $v) = @_;
	unless (
		blessed($v) &&
		$v->isa('RDF::Trine::Node') &&
		($v->is_resource() || $v->is_literal() || $v->is_nil())
	) {
		if (ref($v))
		{
			my $pname = $irik->uri_value();
			die(qq|Invalid field data for property: "$pname"|);
		}
		elsif (! defined $v)
		{
			$v = new RDF::Trine::Node::Nil();
		}
		else
		{
			$v = literal($v);
		}
	}
	#print Dumper($subject, $irik, $v);
	$model->add_statement(statement($subject, $irik, $v));
}

sub decode_instance
{
	my ($obj, $param) = get_param(@_);
	my $subject = $param->{'iri'};
	if (! defined($subject) && defined($param->{'uri'}))
	{
		$subject = iri($param->{'uri'});
	}
	my $model = $param->{'model'};
	unless (blessed($subject) && $subject->isa('RDF::Trine::Node::Resource'))
	{
		die('Invalid instance subject');
	}
	unless (blessed($model) && $model->isa('RDF::Trine::Model'))
	{
		die('Invalid instance model');
	}
	my $stmtiter = $model->get_statements($subject, undef, undef);
	my $mapinv = $obj->map_inverse();
	my %res = ();
	while (my $st = $stmtiter->next())
	{
		my $prop = $st->predicate()->uri_value();
		my $v = $st->object();
		if (exists $mapinv->{$prop})
		{
			my $k = $mapinv->{$prop};
			if ($v->is_literal())
			{
				$v = $v->literal_value();
			}
			#print Dumper($v);
			if (exists $res{$k})
			{
				if (reftype($res{$k}) eq 'ARRAY' && ! $res{$k}->isa('RDF::Trine::Node'))
				{
					push @{$res{$k}}, $v;
				}
				else
				{
					$res{$k} = [$res{$k}, $v];
				}
			}
			else
			{
				$res{$k} = $v;
			}
		}
	}
	return \%res;
}

1;

