package Note::SQL::Abstract;

# Based on DBIx::Abstract

use strict;
use vars qw();

sub new
{
	my $class = shift;
	my $obj = {};
	bless $obj, $class;
	return $obj;
}

sub __where {
	my($self,$where,$int) = @_;
	# $where == This is either a scalar, hash-ref or array-ref
	#					 If it is a scalar, then it is used as the literal where.
	#					 If it is a hash-ref then the key is the field to check,
	#					 the value is either a literal value to compare equality to,
	#					 or an array-ref to an array of operator and value.
	#						 {first=>'joe',age=>['>',26],last=>['like',q|b'%|]}
	#					 Would produce:
	#						 WHERE first=? AND age > ? AND last is like ?
	#						 and add joe, 26 and b'% to the bind_params list
	#					 If it is an array-ref then it is an array of hash-refs and
	#					 connectors:
	#						 [{first=>'joe',age=>['>',26]},'OR',{last=>['like',q|b'%|]}]
	#					 Would produce:
	#						 WHERE (first=? AND age > ?) OR (last like ?)
	#						 and add joe, 26 and b'% to the bind_params list
	my $result='';
	my @bind_params;
	$int ||= 0;

	if ($int > 20) {
		die "Note::Abstract Where parser iterated too deep, circular reference in where clause?\n";
	}

	if (ref($where) eq 'ARRAY') {
		foreach (@$where) {
			if (ref($_) eq 'HASH') {
				my($moreres,@morebind) = $self->__where_hash($_);
				$result .= "($moreres)" if $moreres;
				push(@bind_params,@morebind);
			} elsif (ref($_) eq 'ARRAY') {
				my($moreres,@morebind) = $self->__where($_,$int+1);
				$result .= "($moreres)" if $moreres;
				push(@bind_params,@morebind);
			} else {
				$result .= " $_ ";
			}
		}
	} elsif (ref($where) eq 'HASH') {
		my($moreres,@morebind) = $self->__where_hash($where);
		$result = $moreres;
		@bind_params = @morebind;
	} else {
		$result = $where;
	}
	if ($result) {
		return ($int?'':' WHERE ').$result,@bind_params;
	} else {
		return '';
	}
}

sub __where_hash {
	my($self,$where) = @_;
	my $ret;
	my @bind_params;
	foreach (keys(%$where)) {
		if ($ret) { $ret .= ' AND ' }
		$ret .= "$_ ";
		if (ref($$where{$_}) eq 'ARRAY') {
			$ret .= $$where{$_}[0].' ';
			if (ref($$where{$_}[1]) eq 'SCALAR') {
				$ret .= ${$$where{$_}[1]};
			} else {
				$ret .= '?';
				push(@bind_params,$$where{$_}[1]);
			}
		} else {
			if (defined($$where{$_})) {
				$ret .= '= ';
				if (ref($$where{$_}) eq 'SCALAR') {
					$ret .= ${$$where{$_}};
				} else {
					$ret .= '?';
					push(@bind_params,$$where{$_});
				}
			} else {
				$ret .= 'IS NULL';
			}
		}
	}
	if ($ret ne '()') {
		return $ret,@bind_params;
	} else {
		return '';
	}
}

sub delete {
	my($self,$table,$where) = @_;
	# $table == Name of table to update
	# $where == One of my handy-dandy standard where's.	See __where.
	my($sql,@keys,$i);
	if (ref($table)) {
		$where = $$table{'where'};
		$table = $$table{'table'};
	}

	$table or die 'Note::Abstract: delete must have table';

	my($res,@bind_params) = $self->__where($where);
	$sql = "DELETE FROM $table".$res;
	return $sql, \@bind_params;
}

sub insert {
	my($self,$table,$fields)=@_;
	# $table	== Name of table to update
	# $fields == A reference to a hash of field/value pairs containing the
	#						new values for those fields.
	my(@bind_params);
	if (ref($table)) {
		$fields = $$table{'fields'};
		$table = $$table{'table'};
	}

	$table or die 'Note::Abstract: insert must have table';

	my $sql = "INSERT INTO $table ";
	if (ref($fields) eq 'HASH') {
		my @keys = keys(%$fields);
		my @values = values(%$fields);
		$#keys>-1 or die 'Note::Abstract: insert must have fields';
		$sql .= '(';
		for (my $i=0;$i<=$#keys;$i++) {
			if ($i) { $sql .= ',' }
			$sql .= ' '.$keys[$i];
		}
		$sql .= ') VALUES (';
		for (my $i=0;$i<=$#keys;$i++) {
			if ($i) { $sql .= ', ' }
			if (defined($values[$i])) {
				if (ref($values[$i]) eq 'SCALAR') {
					$sql .= ${$values[$i]};
				} elsif (ref($values[$i]) eq 'ARRAY') {
					$sql .= $values[$i][0];
				} else {
					$sql .= '?';
					push(@bind_params,$values[$i]);
				}
			} else {
				$sql .= 'NULL';
			}
		}
		$sql .= ')';
	} elsif (!ref($fields) and $fields) {
		$sql .= $fields;
	} else {
		die 'Note::Abstract: insert must have fields';
	}
	return $sql, \@bind_params;
}

sub replace {
	my($self,$table,$fields)=@_;
	# $table	== Name of table to update
	# $fields == A reference to a hash of field/value pairs containing the
	#						new values for those fields.
	my(@bind_params);
	if (ref($table)) {
		$fields = $$table{'fields'};
		$table = $$table{'table'};
	}

	$table or die 'Note::Abstract: insert must have table';

	my $sql = "REPLACE INTO $table ";
	if (ref($fields) eq 'HASH') {
		my @keys = keys(%$fields);
		my @values = values(%$fields);
		$#keys>-1 or die 'Note::Abstract: insert must have fields';
		$sql .= '(';
		for (my $i=0;$i<=$#keys;$i++) {
			if ($i) { $sql .= ',' }
			$sql .= ' '.$keys[$i];
		}
		$sql .= ') VALUES (';
		for (my $i=0;$i<=$#keys;$i++) {
			if ($i) { $sql .= ', ' }
			if (defined($values[$i])) {
				if (ref($values[$i]) eq 'SCALAR') {
					$sql .= ${$values[$i]};
				} elsif (ref($values[$i]) eq 'ARRAY') {
					$sql .= $values[$i][0];
				} else {
					$sql .= '?';
					push(@bind_params,$values[$i]);
				}
			} else {
				$sql .= 'NULL';
			}
		}
		$sql .= ')';
	} elsif (!ref($fields) and $fields) {
		$sql .= $fields;
	} else {
		die 'Note::Abstract: insert must have fields';
	}
	$self->__mod_query($sql,@bind_params);
	return $self;
}

sub update {
	my($self,$table,$fields,$where) = @_;
	# $table	 == Name of table to update
	# $fields	== A reference to a hash of field/value pairs containing the
	#						 new values for those fields.
	# $where == One of my handy-dandy standard where's.	See __where.
	my($sql,@keys,@values,$i);
	my(@bind_params);
	if (ref($table)) {
		$where = $$table{'where'};
		$fields = $$table{'fields'};
		$table = $$table{'table'};
	}

	# "If you don't know what to do, don't do anything."
	#					-- St. O'Ffender, _Return of the Roller Blade Seven_
	$table or die 'Note::Abstract: update must have table';

	$sql = "UPDATE $table SET";
	if (ref($fields) eq 'HASH') {
		@keys = keys(%$fields);
		@values = values(%$fields);
		$#keys>-1 or die 'Note::Abstract: update must have fields';
		for ($i=0;$i<=$#keys;$i++) {
			if ($i) { $sql .= ',' }
			$sql .= ' '.$keys[$i].'=';
			if (defined($values[$i])) {
					if (ref($values[$i]) eq 'SCALAR') {
						$sql .= ${$values[$i]};
					} else {
						$sql .= '?';
						push(@bind_params,$values[$i]);
					}
			} else {
					$sql .= 'NULL';
			}
		}
	} elsif (!ref($fields) and $fields) {
		$sql .= " $fields";
	} else {
		die 'Note::Abstract: update must have fields';
	}

	my($moresql,@morebind) = $self->__where($where);
	$sql .= $moresql;
	push(@bind_params,@morebind);
	return $sql, \@bind_params;
}

sub select {
	my $self = shift;
	my($fields,$table,$where,$order,$extra) = @_;
	# $fields	== A hash ref with the following values
	#	 OR
	# $fields	== Fields to get data on, usually a *. (either scalar or
	#						 array ref)
	# $table	 == Name of table to update
	# $where	 == One of my handy-dandy standard where's.	See __where.
	# $order	 == The order to output in
	my $group;#== The key to group by, only available in hash mode
	my($sql,@keys,$i,$join,$left);
	if (ref($fields) eq 'HASH') {
		my $field;
		foreach (keys(%$fields)) {
			my $field = $_;
			$field = lc($field);
			if (/^-(.*)/) { $field = $1 }
			$$fields{$field} = $$fields{$_};
		}
		$table = $$fields{'table'} || $$fields{'tables'};
		$where = $$fields{'where'};
		$order = $$fields{'order'};
		$group = $$fields{'group'};
		$extra = $$fields{'extra'};
		$join	= $$fields{'join'};
		$left	= $$fields{'join_left'};

		$fields = $$fields{'fields'} || $$fields{'field'};
	}
	$sql = 'SELECT ';
	if (ref($fields) eq 'ARRAY') {
		$sql .= join(',',@$fields);
	} else {
		$sql .= $fields;
	}
	if (ref($table) eq 'ARRAY') {
		if ($#$table>-1) {
			$sql.=' FROM '.join(',',@$table);
		}
	} else {
			$sql.=" FROM $table" if $table;
	}

	if (defined $left)
	{
		foreach my $leftjoin (@$left)
		{
			$sql .= ' LEFT JOIN ('. $leftjoin->[0]. ') ON ('. $leftjoin->[1]. ')';
		}
	}

	my($addsql,@bind_params);
	if (defined($where)) {
		($addsql) = $self->__where($where,1);
		unless ($addsql) {
			$where = undef;
		}
	}

	if ($join) {
		unless (ref($join)) {
			$join = [$join];
		}
		if ($where) {
			$where = [$where];
		} else {
			$where = [];
		}
		foreach (@{$join}) {
			push(@$where,'and') if $#$where>-1;
			push(@$where, [$_]);
		}
	}

	if (defined($where)) {
		($addsql,@bind_params) = $self->__where($where);
		$sql .= $addsql;
	}

	if (ref($group) eq 'ARRAY') {
		if ($#$group>-1) {
			$sql .= ' GROUP BY '.join(',',@$group);
		}
	} elsif ($group) {
		$sql .= " GROUP BY $group";
	}

	if (ref($order) eq 'ARRAY') {
		if ($#$order>-1) {
			$sql .= ' ORDER BY '.join(',',@$order);
		}
	} elsif ($order) {
		$sql .= " ORDER BY $order";
	}

	if ($extra) {
		$sql .= ' '.$extra;
	}

	return $sql, \@bind_params;
}

1;

