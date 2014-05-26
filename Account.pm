package Note::Account;
use strict;
use warnings;

BEGIN: {
	use base 'Exporter';
	use vars qw(@EXPORT_OK);
	@EXPORT_OK = qw(create_account transaction account_id tx_type_id has_account);

	use Math::Round 'nearest';
	use POSIX 'strftime';

	use Note::SQL::Table 'sqltable';
	use Note::Row;
};

sub new
{
	my $class = shift;
	my $id = shift;
	my $rc = new Note::Row('account' => {'user_id' => $id});
	unless (defined $rc->id())
	{
		die(qq|Invalid account: '$id'|);
	}
	my $obj = {
		'id' => $rc->id(),
	};
	bless $obj, $class;
	return $obj;
}

sub id
{
	my ($obj) = shift;
	return $obj->{'id'};
}

# static method
sub has_account
{
	my $id = shift;
	my $rc = new Note::Row('account' => {'user_id' => $id});
	return ($rc->id()) ? 1 : 0;
}

# static method
sub account_id
{
	my ($name) = @_;
	my $created = 0;
	my $actrc = Note::Row::find_create('account_name' => {
		'name' => $name,
	}, undef, \$created);
	if ($created)
	{
		my $ac = create_account($actrc->id());
		$actrc->update({'account' => $ac->id()});
		my $obj = {
			'id' => $ac->id(),
		};
		bless $obj, 'Note::Account';
		return $obj;
	}
	else
	{
		my $obj = {
			'id' => $actrc->data('account'),
		};
		bless $obj, 'Note::Account';
		return $obj;
	}
}

# static method
sub tx_type_id
{
	my ($name) = @_;
	my $r = Note::Row::find_create('account_transaction_type' => {
		'name' => $name,
	});
	return $r->id();
}

# static method
# params:
#  owner
sub create_account
{
	my ($owner) = @_;
	my $now = strftime("%F %T", localtime(time()));
	my $rc = Note::Row::create('account', {
		'user_id' => $owner,
		'balance' => 0,
		'ts_created' => $now,
		'ts_updated' => $now,
	});
	return new Note::Account($owner);
}

# static method
# params:
#  acct_src, acct_dst, amount, entity, tx_type, user_id
sub transaction
{
	my (@arg) = @_;
	my $param = (ref($arg[0])) ? $arg[0] : {@arg};
	my $src = $param->{'acct_src'};
	my $dst = $param->{'acct_dst'};
	unless ($src->isa('Note::Account'))
	{
		die('Source not a Note::Account object');
	}
	unless ($dst->isa('Note::Account'))
	{
		die('Destination not a Note::Account object');
	}
	if ($dst->{'id'} == $src->{'id'})
	{
		die('Source and destination accounts must be different');
	}
	my $amt = $param->{'amount'};
	$amt = nearest(0.0001, $amt);
	unless ($amt =~ /^(\-)?\d+(\.\d{1,4})?$/)
	{
		die('Invalid transaction amount: '. $amt);
	}
	my $ts = strftime("%F %T", localtime(time()));
	my $txrec = Note::Row::create('account_transaction', {
		'ts' => $ts,
		'acct_src' => $src->{'id'},
		'acct_dst' => $dst->{'id'},
		'amount' => $amt,
		'entity' => $param->{'entity'},
		'tx_type' => $param->{'tx_type'},
		'user_id' => $param->{'user_id'},
	});
	return $txrec->{'id'};
}

sub balance
{
	my ($obj) = @_;
	return sqltable('account')->get(
		'array' => 1,
		'result' => 1,
		'select' => 'balance',
		'where' => {
			'id' => $obj->{'id'},
		},
	);
}

sub prev_balance
{
	my ($obj, $txid) = @_;
	my $q = sqltable('account_log')->get(
		'array' => 1,
		'result' => 1,
		'select' => 'balance',
		'where' => {
			'last_tx' => ['<', $txid],
			'account' => $obj->{'id'},
		},
		'order' => 'id desc limit 1',
	);
	unless (defined $q)
	{
		return 0;
	}
	return $q;
}

sub history_count
{
	my ($obj, $startts, $endts) = @_;
	my $st = strftime("%F %T", localtime($startts));
	my $en = strftime("%F %T", localtime($endts));
	return sqltable('account_transaction')->get(
		'array' => 1,
		'result' => 1,
		'select' => 'count(id)',
		'where' => [
			"ts >= '$st' and ts <= '$en'",
			'and', [
				{
					'acct_src' => $obj->{'id'},
				},
				'or',
				{
					'acct_dst' => $obj->{'id'},
				},
			],
		],
	);
}

sub history
{
	my ($obj, $startts, $endts, $limit, $offset) = @_;
	my $st = strftime("%F %T", localtime($startts));
	my $en = strftime("%F %T", localtime($endts));
	my $lim = '';
	if (defined $limit && defined $offset)
	{
		$lim .= ' limit '. $limit. ' offset '. $offset;
	}
	my $txlog = sqltable('account_transaction')->get(
		'hash' => 1,
		'select' => ['id', 'amount', 'acct_src', 'acct_dst', 'unix_timestamp(ts)', 'entity', 'user', 'tx_type'],
		'where' => [
			"ts >= '$st' and ts <= '$en'",
			'and', [
				{
					'acct_src' => $obj->{'id'},
				},
				'or',
				{
					'acct_dst' => $obj->{'id'},
				},
			],
		],
		'order' => 'ts desc'. $lim,
	);
	my @log = ();
	my $bb = undef;
	if (scalar @$txlog)
	{
		$bb = $obj->prev_balance($txlog->[-1]->{'id'});
	}
	foreach my $r (reverse @$txlog)
	{
		my $i = {
			'ts' => $r->{'unix_timestamp(ts)'},
			'type' => $r->{'tx_type'},
			'amount' => $r->{'amount'},
			'begin' => $bb,
			'user' => $r->{'user'},
			'entity' => $r->{'entity'},
		};
		if ($r->{'acct_dst'} == $obj->{'id'})
		{
			$i->{'from'} = $r->{'acct_src'};
			$i->{'end'} = $bb + $r->{'amount'};
			$bb += $r->{'amount'};
		}
		elsif ($r->{'acct_src'} == $obj->{'id'})
		{
			$i->{'to'} = $r->{'acct_dst'};
			$i->{'end'} = $bb - $r->{'amount'};
			$bb -= $r->{'amount'};
		}
		push @log, $i;
	}
	@log = reverse (@log);
	return \@log;
}

sub first_ts
{
	my ($obj, $tid) = @_;
	my $whr = [
		[
			{
				'acct_src' => $obj->{'id'},
			},
			'or',
			{
				'acct_dst' => $obj->{'id'},
			},
		]
	];
	if (defined $tid)
	{
		push @$whr, 'and', {
			'tx_type' => $tid,
		};
	}
	my $q = sqltable('account_transaction')->get(
		'array' => 1,
		'result' => 1,
		'select' => 'min(unix_timestamp(ts))',
		'where' => $whr,
	);
	$q ||= time();
	return $q;
}

sub last_ts
{
	my ($obj, $tid) = @_;
	my $whr = [
		[
			{
				'acct_src' => $obj->{'id'},
			},
			'or',
			{
				'acct_dst' => $obj->{'id'},
			},
		]
	];
	if (defined $tid)
	{
		push @$whr, 'and', {
			'tx_type' => $tid,
		};
	}
	my $q = sqltable('account_transaction')->get(
		'array' => 1,
		'result' => 1,
		'select' => 'max(unix_timestamp(ts))',
		'where' => $whr,
	);
	$q ||= time();
	return $q;
}

1;
