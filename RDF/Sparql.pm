package Note::RDF::Sparql;
use strict;
use warnings;
no warnings 'uninitialized';

use vars qw();

use Moose;
use Data::Dumper;
use RDF::Trine ('iri', 'statement', 'literal');
use RDF::Trine::Node;
use RDF::Trine::Store;
use RDF::Query;
use RDF::Query::Client;
use Scalar::Util ('blessed', 'reftype');
use Encode;
use DBI;
use Carp;

use Note::Param;
use Note::RDF::NS ('ns_iri', 'rdf_ns');
use Note::RDF::SAXHandler;
use Note::RDF::SAXHandlerGraph;

no warnings qw(uninitialized);

has 'context' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Node',
	'lazy' => 1,
	'default' => sub {
		return new RDF::Trine::Node::Nil();
	},
);

has 'endpoint' => (
	'is' => 'rw',
	'isa' => 'Str',
);

has 'dbh' => (
	'is' => 'rw',
	'isa' => 'DBI::db',
);

has 'model' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Model',
	'lazy' => 1,
	'default' => sub {
		my ($obj) = @_;
		return new RDF::Trine::Model($obj->storage());
	},
);

has 'storage' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Store',
	'lazy' => 1,
	'default' => sub {
		my ($obj) = @_;
		my $endp = $obj->endpoint();
		if (defined $endp)
		{
			my $store = new RDF::Trine::Store::SPARQL($endp);
			$store->{'ua'}->default_header('Accept' => 'application/sparql-results+xml;q=0.9,application/rdf+xml');
			return $store;
		}
		else
		{
			return new RDF::Trine::Store::Memory();
		}
	},
);

sub get_resource_model
{
	my ($obj, $rsrc, $model) = @_;
	my $propiter = $obj->get_statements(
		$rsrc,
		undef,
		undef,
	);
	$model ||= new RDF::Trine::Model();
	$model->add_iterator($propiter);
	return $model;
}

sub get_owl_sameas
{
	my ($obj, $rsrc) = @_;
	my $sameAs = ns_iri('owl', 'sameAs')->uri_value();
	my $qry = $obj->build_sparql(
		'from' => 0,
		#'debug' => 1,
		'select' => ['distinct ?same'],
		'where' => <<WHERE,
{
	{
		SELECT ?item ?same
		WHERE {
			{
				?item <$sameAs> ?same
			} UNION {
				?same <$sameAs> ?item
			}
		}
	}
	OPTION (transitive, t_in (?item), t_out (?same), t_distinct, t_min (0))
}
WHERE
		'filter' => {
			'?item' => $rsrc,
		},
	);
	my $orig = $rsrc->uri_value();
	my @res = ();
	while (my $r = $qry->next())
	{
		next if ($r->{'same'}->uri_value() eq $orig);
		push @res, $r->{'same'};
	}
	@res = sort {
		$a->uri_value() cmp $b->uri_value()
	} @res; # sort uris
	unshift @res, iri($orig); # make original first
	return \@res;
}

sub get_expanded_model
{
	my ($obj, $rsrc, $model) = @_;
	my $sameAs = ns_iri('owl', 'sameAs')->uri_value();
	my $qry = $obj->build_sparql(
		'from' => 0,
		#'debug' => 1,
		'select' => ['distinct ?same'],
		'where' => <<WHERE,
{
	{
		SELECT ?item ?same
		WHERE {
			{
				?item <$sameAs> ?same
			} UNION {
				?same <$sameAs> ?item
			}
		}
	}
	OPTION (transitive, t_in (?item), t_out (?same), t_distinct, t_min (0))
}
WHERE
		'filter' => {
			'?item' => $rsrc,
		},
	);
	$model ||= new RDF::Trine::Model();
	while (my $r = $qry->next())
	{
		#::_log($r);
		$obj->get_resource_model($r->{'same'}, $model);
	}
	return $model;
}

sub add_statement
{
	my ($obj, $stmt, $prdc, $val) = @_;
	unless (blessed($stmt) && $stmt->isa('RDF::Trine::Statement'))
	{
		if (
			(blessed($stmt) && $stmt->isa('RDF::Trine::Node')) &&
			(blessed($prdc) && $prdc->isa('RDF::Trine::Node')) &&
			(blessed($val) && $val->isa('RDF::Trine::Node'))
		) {
			$stmt = statement($stmt, $prdc, $val);
		}
		else
		{
			die(qq|Invalid statement: '$stmt'|);
		}
	}
	$obj->insert('statement' => $stmt);
}

sub query
{
	my ($obj, $param) = get_param(@_);
	my $endp = $obj->endpoint();
	my $dbh = $obj->dbh();
	my $iter = undef;
	if (defined $dbh)
	{
		my $sth = $dbh->prepare('SPARQL define output:format "RDF/XML" '. $param->{'sparql'}) or die('DBI Error: '. $dbh->errstr());
		$sth->execute() or die('DBI Error: '. $dbh->errstr());
		$sth->bind_col(1, undef, {'TreatAsLOB' => 1});
		my $res = $sth->fetchrow_arrayref();
		my $rdf = '';
		while($sth->odbc_lob_read(1, \my $data, 1024)) {
			$rdf .= $data;
		}
		$rdf = encode('UTF-8', $rdf);
		my $handler = Note::RDF::SAXHandler->new();
		my $p = XML::SAX::ParserFactory->parser(Handler => $handler);
		eval {
			$p->parse_string($rdf);
		};
		if ($@)
		{
			print STDERR "XML Parse Failed:\n$rdf\n---\n";
			die($@);
		}
		my $iter = $handler->iterator();
		return $iter;
	}
	elsif (defined $endp)
	{
		my $cli = new RDF::Query::Client($param->{'sparql'});
		$iter = $cli->execute($endp);
		unless (defined $iter)
		{
			die('RDF Query Error: '. $cli->error());
		}
	}
	else
	{
		my $qry = new RDF::Query($param->{'sparql'});
		#print $obj->model()->as_string();
		$iter = $qry->execute($obj->model());
		unless (defined $iter)
		{
			die('RDF Query Error: '. $qry->error());
		}
	}
	return $iter;
}

sub insert
{
	my ($obj, $param) = get_param(@_);
	my $store = $obj->storage();
	my $stmt;
	if (defined $param->{'statement'})
	{
		$stmt = $param->{'statement'};
	}
	else
	{
		$stmt = statement($param->{'subject'}, $param->{'predicate'}, $param->{'object'});
	}
	my $ctxt = $obj->context();
	my $endp = $obj->endpoint();
	my $dbh = $obj->dbh();
	if (defined $dbh)
	{
		my $sparql = 'SPARQL define output:format "RDF/XML" INSERT IN GRAPH '. $ctxt->as_ntriples(). ' { ';
		$sparql .= join(' ', map { $_->as_ntriples() } $stmt->nodes()). '.';
		$sparql .= ' }';
		#::_log("ODBC Sparql:". $sparql);
		my $sth = $dbh->prepare($sparql) or die('DBI Error: '. $dbh->errstr());
		#::_log("ODBC Prepared");
		$sth->execute() or die('DBI Error: '. $dbh->errstr());
		#::_log("ODBC Executed");
		$sth->bind_col(1, undef, {TreatAsLOB=>1});
		my $res = $sth->fetchrow_arrayref();
		my $output = '';
		while($sth->odbc_lob_read(1, \my $data, 1024)) {
			$output .= $data;
		}
		$output = encode('UTF-8', $output);
		return $output;
		#::_log("ODBC Insert Output:", $output);
	}
	elsif (defined $endp)
	{
		my $sparql = 'INSERT IN GRAPH '. $ctxt->as_ntriples(). ' { ';
		$sparql .= join(' ', map { $_->as_ntriples() } $stmt->nodes()). '.';
		$sparql .= ' }';
		my $resp = $store->{'ua'}->post($store->{'url'}, {'query' => $sparql});
		#print "SPARQL Insert Reply: ". $resp->status_line(). "\n". $resp->content();
		unless ($resp->is_success())
		{
			die("SPARQL Insert Reply: ". $resp->status_line(). "\n". $resp->content());
		}
	}
	else
	{
		#$store->add_statement($stmt, $ctxt);
		$store->add_statement($stmt);
	}
}

sub delete
{
	my ($obj, $param) = get_param(@_);
	my $store = $obj->storage();
	my $stmt;
	if (defined $param->{'statement'})
	{
		$stmt = $param->{'statement'};
	}
	else
	{
		$stmt = statement($param->{'subject'}, $param->{'predicate'}, $param->{'object'});
	}
	my $ctxt = $obj->context();
	my $endp = $obj->endpoint();
	my $dbh = $obj->dbh();
	if (defined $dbh)
	{
		my $sparql = 'SPARQL define output:format "RDF/XML" DELETE FROM GRAPH '. $ctxt->as_ntriples(). ' { ';
		$sparql .= join(' ', map { $_->as_ntriples() } $stmt->nodes()). '.';
		$sparql .= ' }';
		#::_log("ODBC Sparql:". $sparql);
		my $sth = $dbh->prepare($sparql) or die('DBI Error: '. $dbh->errstr());
		#::_log("ODBC Prepared");
		$sth->execute() or die('DBI Error: '. $dbh->errstr());
		#::_log("ODBC Executed");
		$sth->bind_col(1, undef, {TreatAsLOB=>1});
		my $res = $sth->fetchrow_arrayref();
		my $output = '';
		while($sth->odbc_lob_read(1, \my $data, 1024)) {
			$output .= $data;
		}
		$output = encode('UTF-8', $output);
		return $output;
		#::_log("ODBC Insert Output:", $output);
	}
	elsif (defined $endp)
	{
		my $sparql = 'DELETE FROM GRAPH '. $ctxt->as_ntriples(). ' { ';
		$sparql .= join(' ', map { $_->as_ntriples() } $stmt->nodes());
		$sparql .= ' }';
		my $resp = $store->{'ua'}->post($store->{'url'}, {'query' => $sparql});
		#print "SPARQL Delete Reply: ". $resp->status_line(). "\n". $resp->content();
		unless ($resp->is_success())
		{
			die("SPARQL Delete Reply: ". $resp->status_line(). "\n". $resp->content());
		}
	}
	else
	{
		$store->remove_statement($stmt, $ctxt);
	}
}

sub get_statements
{
	my ($obj, $subj, $pred, $val) = @_;
	my $dbh = $obj->dbh();
	if (defined $dbh)
	{
		my @whr = ();
		my @sel = ();
		my %wg = ();
		if (defined $subj)
		{
			$whr[0] = $subj;
			$wg{'s'} = $subj;
		}
		else
		{
			$whr[0] = '?s';
			push @sel, '?s';
		}
		if (defined $pred)
		{
			$whr[1] = $pred;
			$wg{'p'} = $pred;
		}
		else
		{
			$whr[1] = '?p';
			push @sel, '?p';
		}
		if (defined $val)
		{
			$whr[2] = $val;
			$wg{'v'} = $val;
		}
		else
		{
			$whr[2] = '?v';
			push @sel, '?v';
		}
		my $sparql = $obj->build_sparql(
			'query' => 0,
			'from' => 0,
			'select' => \@sel,
			'where' => [\@whr],
		);
		my $sth = $dbh->prepare('SPARQL define output:format "RDF/XML" '. $sparql) or die('DBI Error: '. $dbh->errstr());
		$sth->execute() or die('DBI Error: '. $dbh->errstr());
		$sth->bind_col(1, undef, {'TreatAsLOB' => 1});
		my $res = $sth->fetchrow_arrayref();
		my $rdf = '';
		while($sth->odbc_lob_read(1, \my $data, 1024)) {
			$rdf .= $data;
		}
		$rdf = encode('UTF-8', $rdf);
		my $handler = Note::RDF::SAXHandlerGraph->new(\%wg);
		my $p = XML::SAX::ParserFactory->parser('Handler' => $handler);
		eval {
			$p->parse_string($rdf);
		};
		if ($@)
		{
			print STDERR "XML Parse Failed:\n$rdf\n---\n";
			die($@);
		}
		my $iter = $handler->iterator();
		return $iter;
	}
	return $obj->storage()->get_statements($subj, $pred, $val, $obj->context());
}

sub build_sparql
{
	my ($obj, $param) = get_param(@_);
	my $sparql = '';
	my %ks = ();
	my %prefix = ();
	if (exists($param->{'prefix'}) && reftype($param->{'prefix'}) eq 'HASH')
	{
		%prefix = %{$param->{'prefix'}};
	}
	my @where = ();
	my $build_where = sub {
		my $wh = shift;
		my $extra = '';
		if (! ref($wh->[0]))
		{
			if ($wh->[0] =~ /^\?/)
			{
				$ks{$wh->[0]} = 1;
			}
			elsif ($wh->[0] =~ /^(\w+)\:$/)
			{
				$prefix{$1} ||= rdf_ns($1);
			}
		}
		else
		{
			$wh->[0] = $wh->[0]->as_ntriples();
		}
		if (! ref($wh->[1]))
		{
			if ($wh->[1] =~ /^\?/)
			{
				$ks{$wh->[1]} = 1;
			}
			elsif ($wh->[1] eq 'bif:contains') # OpenLink Virtuoso Extension - Full Text Search
			{
				if ($wh->[3] =~ /^\s*option/i)
				{
					$extra = $wh->[3];
					$wh->[3] = undef;
					$#{$wh} = 2;
				}
			}
			elsif ($wh->[1] =~ /^(\w+)\:/)
			{
				$prefix{$1} ||= rdf_ns($1);
			}
		}
		else
		{
			$wh->[1] = $wh->[1]->as_ntriples();
		}
		if (! ref($wh->[2]))
		{
			if ($wh->[2] =~ /^\?/)
			{
				$ks{$wh->[2]} = 1;
			}
			elsif ($wh->[2] =~ /^(\w+)\:/)
			{
				$prefix{$1} ||= rdf_ns($1);
			}
		}
		elsif (! blessed($wh->[2]))
		{
			if (reftype($wh->[2]) eq 'SCALAR')
			{
				$wh->[2] = literal(${$wh->[2]}, undef, ns_iri('xsd', 'string'))->as_ntriples();
			}
			elsif (reftype($wh->[2]) eq 'ARRAY')
			{
				my $ty = $wh->[2]->[1];
				if (blessed($ty) && $ty->isa('RDF::Trine::Node::Resource'))
				{
					$wh->[2] = literal($wh->[2]->[0], undef, $ty)->as_ntriples();
				}
				else
				{
					$ty =~ /^(\w+)\:(.*)$/;
					$prefix{$1} ||= rdf_ns($1);
					$wh->[2] = literal($wh->[2]->[0], undef, ns_iri($1, $2))->as_ntriples();
				}
			}
		}
		else
		{
			$wh->[2] = $wh->[2]->as_ntriples();
		}
		if ($extra)
		{
			$wh->[2] .= ' '. $extra;
		}
	};
	my $where_iter;
	$where_iter = sub {
		my $where = shift;
		my @res = ();
		foreach my $wh (@$where)
		{
			unless (reftype($wh) eq 'ARRAY')
			{
				die(qq|Invalid where clause: '$wh'|);
			}
			if (
				(! ref($wh->[0])) &&
				$wh->[0] =~ /^optional$/i &&
				ref($wh->[1]) && reftype($wh->[1]) eq 'ARRAY'
			) {
				my $sparql = "OPTIONAL {\n";
				my @part = $where_iter->($wh->[1]);
				$sparql .= join("\n", map {"\t$_"} @part). "\n";
				if (ref($wh->[2]) && reftype($wh->[2]) eq 'HASH')
				{
					my $flt = $wh->[2];
					if (ref($flt))
					{
						$flt = $obj->_sparql_filter($flt);
					}
					if (defined $flt)
					{
						$sparql .= "FILTER $flt";
					}
				}
				$sparql .= "}\n";
				push @res, $sparql;
			}
			elsif (
				(! ref($wh->[0])) &&
				$wh->[0] =~ /^union$/i &&
				ref($wh->[1]) && reftype($wh->[1]) eq 'ARRAY'
			) {
				my @union = ();
				foreach my $nextwh (@{$wh->[1]})
				{
					my @part = $where_iter->($nextwh);
					my $element = join("\n", map {"\t$_"} @part). "\n";
					push @union, $element;
				}
				my $sparql = join 'UNION ', map {"{\n$_\n}\n"} @union;
				push @res, $sparql;
			}
			else
			{
				$build_where->($wh);
				push @res, join(' ', @$wh). '.';
			}
		}
		return @res;
	};
	if (exists($param->{'where'}))
	{
		if (ref($param->{'where'}) && reftype($param->{'where'}) eq 'ARRAY')
		{
			push @where, $where_iter->($param->{'where'});
		}
		elsif ((! ref($param->{'where'})) && length($param->{'where'}))
		{
			push @where, $param->{'where'};
		}
	}
	#print STDERR Dumper(\%prefix);
	foreach my $k (sort keys %prefix)
	{
		my $pval = $prefix{$k};
		if (length($pval))
		{
			$sparql .= "PREFIX $k: <$pval>\n";
		}
	}
	$sparql .= 'SELECT ';
	if ($param->{'distinct'})
	{
		$sparql .= 'DISTINCT ';
	}
	if (defined($param->{'select'}) && reftype($param->{'select'}) eq 'ARRAY')
	{
		$sparql .= join(' ', @{$param->{'select'}});
	}
	else
	{
		$sparql .= join(' ', sort keys %ks);
	}
	$sparql .= "\n";
	if (defined $param->{'from'})
	{
		unless ($param->{'from'} eq '0')
		{
			$sparql .= 'FROM ';
			$sparql .= '<'. $param->{'from'}. '>';
			$sparql .= "\n";
		}
	}
	else
	{
		$sparql .= 'FROM ';
		$sparql .= $obj->context()->as_ntriples();
		$sparql .= "\n";
	}
	if (scalar @where)
	{
		$sparql .= "WHERE {\n";
		$sparql .= join("\n", map {"\t$_"} @where). "\n";
		if (exists $param->{'option'}) # Virtuoso OPTION - for TRANSITIVE operation
		{
			$sparql .= "OPTION (\n$param->{'option'}\n) .\n";
		}
		if (exists $param->{'filter'})
		{
			my $flt = $param->{'filter'};
			if (ref($flt))
			{
				$flt = $obj->_sparql_filter($flt);
			}
			if (defined $flt)
			{
				$sparql .= "FILTER $flt";
			}
		}
		$sparql .= "}\n";
	}
	if ($param->{'group'})
	{
		$sparql .= "GROUP BY $param->{'group'}\n";
	}
	if ($param->{'order'})
	{
		$sparql .= "ORDER BY $param->{'order'}\n";
	}
	if ($param->{'limit'})
	{
		$sparql .= "LIMIT $param->{'limit'}\n";
		if ($param->{'offset'})
		{
			$sparql .= "OFFSET $param->{'offset'}\n";
		}
	}
	print STDERR ("SPARQL:\n$sparql") if ($param->{'debug'});
	unless ($param->{'query'} eq '0')
	{
		return $obj->query('sparql' => $sparql);
	}
	return $sparql;
}

sub _sparql_filter
{
	my ($obj, $flt) = @_;
	if (reftype($flt) eq 'ARRAY')
	{
		my @pts = ();
		foreach my $r (@$flt)
		{
			if (ref($r))
			{
				push @pts, $obj->_sparql_filter($r);
			}
			else
			{
				push @pts, $r;
			}
		}
		return '('. join(' ', @pts). ')';
	}
	elsif (reftype($flt) eq 'HASH')
	{
		my @pts = ();
		my @ks = sort keys %$flt;
		foreach my $k (@ks)
		{
			my $r = $flt->{$k};
			if (ref($r))
			{
				if (blessed($r) && $r->isa('RDF::Trine::Node'))
				{
					if ($r->is_literal() || $r->is_resource())
					{
						push @pts, $k. ' = '. $r->as_ntriples();
					}
				}
			}
		}
		unless (scalar @pts)
		{
			return undef;
		}
		return '('. join(' && ', @pts). ')';
	}
}

sub get_rdf_list
{
	my ($obj, $param) = get_param(@_);
	my $list = $param->{'list'};
	my @res = ();
	my $getitem;
	$getitem = sub {
		my ($ls) = @_;
		my $i = $obj->build_sparql(
			'select' => ['?first', '?rest'],
			'where' => [
				[$ls, ns_iri('rdf', 'first'), '?first'],
				[$ls, ns_iri('rdf', 'rest'), '?rest'],
			],
		);
		my $r = $i->next();
		if (defined $r)
		{
			return $r;
		}
		return undef;
	};
	while (my $i = $getitem->($list))
	{
		push @res, $i->{'first'};
		if ($i->{'rest'}->is_nil())
		{
			last;
		}
		$list = $i->{'rest'};
	}
	return \@res;
}

sub iri_exists
{
	my ($obj, $param) = get_param(@_);
	my $ir = $param->{'iri'};
	my $q = $obj->build_sparql(
		'from' => 0,
		#'debug' => 1,
		'select' => ['(count(distinct ?inst) as ?count)'],
		'where' => [
			['?inst', '?attr', '?val'],
		],
		'filter' => {
			'?inst' => $ir,
		},
	);
	my $ct = 0;
	if (my $r = $q->next())
	{
		$ct = $r->{'count'}->literal_value();
	}
	return $ct;
}

1;

