# StructureGraph.pm, used for creating visualizations of patterns
# Author: John Sekar (johnarul.sekar@gmail.com)

package StructureGraph;
# pragmas
use strict;
use warnings;
no warnings 'redefine';

# Perl Modules
use Class::Struct;
use List::Util qw(min max sum);
use Data::Dumper;

# BNG Modules
use SpeciesGraph;

# Notes for self
# Only pass array and hash references to subroutines using \@ and \%
# Dereference using @{...} and %{...}

struct Node => 
{ 
	'Type' => '$', #must be one of 'Mol', 'Comp', 'BondState', 'CompState', 'GraphOp'
	'Name' => '$', 
	'ID' => '$', #only one id is used for each node
	'Parents' => '@', 
	'Side' => '$'
}; 

struct StructureGraph => { 'Type' => '$', 'NodeList' => '@' };

sub makeNode
{
	# input in this order Type, Name, ID, Parents, Side
	# type and name are compulsory, rest are not
	my $node = Node->new();
	$node->{'Type'} = shift @_;
	$node->{'Name'} = shift @_;
	$node->{'ID'} = @_ ? shift @_ : 0;
	$node->{'Parents'} = @_ ? shift @_ : ();
	$node->{'Side'} = @_ ? shift @_ : ();
	return $node;
}

sub makeStructureGraph
{
	# input is Type, NodeList
	my $psg = StructureGraph->new();
	$psg->{'Type'} = $_[0];
	$psg->{'NodeList'} = $_[1];
	return $psg;
}

sub printNode
{
	my $node = $_;
	my $string = $node->{'ID'};
	$string .= "\t\t";
	$string .= $node->{'Name'};
	if ($node->{'Parents'})
	{
		$string .= "\t\t";
		$string .= "(".join(",",@{$node->{'Parents'}} ).")";
	}
	
	if ($node->{'Side'})
	{
		$string .= "\t\t";
		$string .= $node->{'Side'};
	}
	return $string;
}


sub printGraph 
{
	my $psg = shift @_;
	my @string = map {printNode()} @{$psg->{'NodeList'}};
	return $psg->{'Type'}."\n".join("\n",@string);
}


sub makePatternStructureGraph
{
	my $sg = shift @_;
	my $index = @_ ? shift @_ : 0; # this is the index of the pattern in some list of patterns
	
	my @nodelist = ();
	
	if ( $sg->isNull() != 0) { return undef;}
	
	# Nodes for molecules, assigned the ID p.m, where p is the index of the pattern
	# index must be passed to this method.
	my $imol = 0;
	foreach my $mol ( @{$sg->Molecules} )
	{
		my $mol_id = $index.".".$imol;
		push @nodelist, makeNode('Mol',$mol->Name,$mol_id);
		
		# Nodes for components, assigned the ID p.m.c
		my $icomp = 0;
		foreach my $comp( @{$mol->Components} )
		{
			my $comp_id = $mol_id.".".$icomp;
			my @parents = ($mol_id);
			push @nodelist, makeNode('Comp',$comp->Name,$comp_id,\@parents);
			
			# Nodes for internal states, assigned the ID p.m.c.0
			if (defined $comp->State) 
				{ 
					my $state_id = $comp_id.".0";
					my @parents = ($comp_id);
					push @nodelist, makeNode('CompState',$comp->State,$state_id,\@parents);
				}
			
			# Nodes for each wildcard bond (either !? or !+), assigned the ID p.m.c.1
			if (scalar @{$comp->Edges} > 0) 
			{ 
				my $bond_state = ${$comp->Edges}[0];
				if ($bond_state =~ /^[\+\?]$/)
				{
					my $bond_id = $comp_id.".1";
					my @parents = ($comp_id);
					push @nodelist, makeNode('BondState',$bond_state,$bond_id,\@parents);	
				}
			}
			$icomp++;
		}
		$imol++;
	}
	# Nodes for each specified bond, assigned the ID p.m1.c1.1, 
	# where m1.c1 and m2.c2 are the bonded components, sorted. 
	# specified bonds are all assigned the same name "+"
	# only one id is used for each node
	if (scalar @{$sg->Edges} > 0) 
		{
			foreach my $edge (@{$sg->Edges}) 
				{ 
				my @comps = sort split(/ /,$edge);
				my $bond_id = $index.".".$comps[0].".1";
				my @parents = map {$index.".".$_} @comps;
				push @nodelist, makeNode('BondState',"+",$bond_id,\@parents);	
				}
		}
	my $psg = makeStructureGraph('Pattern',\@nodelist);
	#print $psg->printGraph();
	return $psg;	
}

# operations on structure graphs
sub combine
{
	my @psg_list =  @{shift @_};
	my $index =  @_ ? shift @_ : "";
	
	my $type = $psg_list[0]->{'Type'};
	my @nodelist = ();
	
	foreach my $psg(@psg_list) 
		{ 
			my @nodes = @{$psg->{'NodeList'}};
			foreach my $node (@nodes)
				{
					my $id = $node->{'ID'};
					$node->{'ID'} = $index.".".$id;
					if (defined $node->{'Parents'})
						{ 
						my @parents_idlist = @{$node->{'Parents'}};
						my @parents_idlist_new = map {$index.".".$_} @parents_idlist;
						$node->{'Parents'} = \@parents_idlist_new;
						}
				}
			push @nodelist, @nodes;
		}	
	my $psg1 = makeStructureGraph($type,\@nodelist);
	return $psg1;
}

sub findNode
{
	my @nodelist = @{shift @_};
	my $idcheck = shift @_;	
	my @nodes = grep ($_->{'ID'} eq $idcheck,@nodelist);
	if (@nodes) {return $nodes[0];} 
	return 0;
}

sub findNodes
{
	my @nodelist = @{shift @_};
	my @idlist = @{shift @_};
	my @nodes;
	foreach my $idcheck(@idlist)
		{
		my $node = findNode(\@nodelist,$idcheck);
		if ($node) { push @nodes, $node;}
		}
	return @nodes;
}

sub hasType
{
	my @nodelist = @{shift @_};
	my $type = shift @_;
	my @nodes = grep ( $_->{'Type'} eq $type, @nodelist);
	return @nodes;
}

sub hasSide
{
	my @nodelist = @{shift @_};
	my $side = shift @_;
	my @nodes = grep ( $_->{'Side'} eq $side, @nodelist);
	return @nodes;
}

sub hasParent
{
	my @nodelist = @{shift @_};
	my $parent_id = shift @_;
	my @nodes;
	foreach my $node (@nodelist)
		{
		if ($node->{'Parents'})
			{
			my @parents = @{$node->{'Parents'}};
			if (grep($_ eq $parent_id, @parents)) 
				{push @nodes, $node;}
			}
		}
	return @nodes;
}

sub hasParents
{
	my @nodelist = @{shift @_};
	my @parent_ids = @{shift @_};
	my @nodes;
	@nodes = @nodelist;
	foreach my $parent_id ( @parent_ids)
	{
		my @nodes2 = hasParent(\@nodes,$parent_id);
		if (@nodes2) { @nodes = @nodes2; }
		else { return (); }
	}
	return @nodes;
}

sub remapIDs
{
	my $node = shift @_;
	my %remap = %{shift @_};
	my $id = $node->{'ID'};
	$node->{'ID'} = $remap{$id};
	if ($node->{'Parents'})
	{
		my @parents = @{$node->{'Parents'}};
		my @new_parents = sort map ( $remap{$_}, @parents);
		$node->{'Parents'} = \@new_parents;
	}
}

sub mergeCorrespondent
{
	my %mapf = %{shift @_}; # these maps should have been modified and extended
	my %mapr = %{shift @_};

	my $reac = shift @_; # should be a combined structure graph of patterns
	my $prod = shift @_;
	
	my @reac_nodelist = @{$reac->{'NodeList'}};
	my @prod_nodelist = @{$prod->{'NodeList'}};
	
	# i.e. mapping correspondent IDs on both sides of a rule
	# to a single canonical ID
	my %idmap;
	while (my ($key, $value) = each %mapf)
	{
		$idmap{$key} = $key;
	}
	while (my ($key, $value) = each %mapr)
	{
		$idmap{$key} = ($value eq "-1") ? $key : $value;
	}

	my @nodelist = ();
	
	foreach my $node (@reac_nodelist)
	{
		#check if it has a correspondence
		if ($mapf{$node->{'ID'}} ne "-1")
			{
			remapIDs($node,\%idmap);
			$node->{'Side'} = 'both';
			push @nodelist, $node;
			}
		else
			{
			remapIDs($node,\%idmap);
			$node->{'Side'} = 'left';
			push @nodelist, $node;
			}
	}
	foreach my $node (@prod_nodelist)
	{
	if ($mapr{$node->{'ID'}} eq "-1")
			{
			remapIDs($node,\%idmap);
			$node->{'Side'} = 'right';
			push @nodelist, $node;
			}
	}
	my $rsg = makeStructureGraph('Rule',\@nodelist);
	return $rsg;
}

sub addGraphOperations
{
	my $rsg = shift @_;
	my @nodelist = @{$rsg->{'NodeList'}};
	
	my $id = -1;
	
	# identify modified bonds
	my @bondstates = hasType(\@nodelist,'BondState');
	my @delbonds = hasSide(\@bondstates,'left');
	my @addbonds = hasSide(\@bondstates,'right');
	
	my @mols = hasType(\@nodelist,'Mol');
	my @left_mols = hasSide(\@mols,'left');
	my @right_mols = hasSide(\@mols,'right');
	
	my @compstates = hasType(\@nodelist,'CompState');
	my @left_compstates = hasSide(\@compstates,'left');
	my @right_compstates = hasSide(\@compstates,'right');

	# transcribing the graph operations in order
	# this order will be used later to process context
	# order: ChangeState, deletebond/deletemol, addbond/addmol
	
	foreach my $left_compstate (@left_compstates)
	{
		# find the partner on the right
		my $comp_id = ${$left_compstate->{'Parents'}}[0];
		my @partner = hasParent(\@right_compstates,$comp_id);
		# partner may not exist, in case of deletion
		if (@partner)
			{
				my $left_id = $left_compstate->{'ID'};
				my $right_id = $partner[0]->{'ID'};
				my $name = 'ChangeState';
				my @parents = ($left_id,$right_id);
				push @nodelist, makeNode('GraphOp',$name,++$id,\@parents);
			}
	}
	
	foreach my $bondstate(@delbonds)
	{
		my $bond_id = $bondstate->{'ID'};
		my $name = 'DeleteBond';
		my @parents = ($bond_id);
		push @nodelist, makeNode('GraphOp',$name,++$id,\@parents);
	}

	foreach my $mol (@left_mols)
	{
		my $mol_id = $mol->{'ID'};
		my $name = 'DeleteMol';
		my @parents = ($mol_id);
		push @nodelist, makeNode('GraphOp',$name,++$id,\@parents);
	}
	
	foreach my $bondstate(@addbonds)
	{
		my $bond_id = $bondstate->{'ID'};
		my $name = 'AddBond';
		my @parents = ($bond_id);
		push @nodelist, makeNode('GraphOp',$name,++$id,\@parents);
	}

	foreach my $mol (@right_mols)
	{
		my $mol_id = $mol->{'ID'};
		my $name = 'AddMol';
		my @parents = ($mol_id);
		push @nodelist, makeNode('GraphOp',$name,++$id,\@parents);
	}
	
	my $rsg1 = makeStructureGraph('Rule',\@nodelist);
	return $rsg1;
}


sub makeRuleStructureGraph
{
	# Get rule reactants and products and map
	my $rr = shift @_;
	my @reac = @{$rr->Reactants};
	my @prod= @{$rr->Products};
	my %mapf = %{$rr->MapF};
	my %mapr = %{$rr->MapR};
	
	# the correspondence hash needs to be modified to add
	# reactant/product indexes to IDs
	%mapf = modifyCorrespondenceHash(\%mapf,0,1);
	%mapr = modifyCorrespondenceHash(\%mapr,1,0);
	
	# Make combined structure graphs of reactant and product patterns respectively
	my %ind_reac = indexHash(\@reac);
	my %ind_prod = indexHash(\@prod);
	
	my @reac_psg = map( makePatternStructureGraph($_,$ind_reac{$_}), @reac);
	my @prod_psg = map( makePatternStructureGraph($_,$ind_prod{$_}), @prod);
	
	my $reac_psg1 = combine(\@reac_psg,"0");
	my $prod_psg1 = combine(\@prod_psg,"1");
	
	# the correspondence hash needs to be extended 
	# to include component states & bonds
	my ($mapf1,$mapr1) = extendCorrespondenceHash(\%mapf,\%mapr,$reac_psg1,$prod_psg1);
	%mapf = %$mapf1;
	%mapr = %$mapr1;
	
	# merge the nodes to generate the 'implicit' rule structure graph
	my $rsg = mergeCorrespondent(\%mapf,\%mapr,$reac_psg1,$prod_psg1);
	
	# add the graph operation nodes to generate
	# the 'explicit' rule structure graph
	my $rsg1 = addGraphOperations($rsg);
	return $rsg1;	
}

# functions dealing with hashes
sub indexHash
{
	my %indhash;
	my @list = @{shift @_};
	foreach my $i(0..@list-1) { $indhash{$list[$i]}=$i; }
	return %indhash;
}

sub printHash
{
	my %hash = %{shift @_};
	my $string = "\n";
	while ( my ($key,$value) = each %hash)
	{
		$string .= "$key\t\t$value\n";
	}
	return $string;
}

sub modifyCorrespondenceHash
{
	# modifying existing keys in place not recommended?
	my %map = %{shift @_};
	my $ind1 = shift @_;
	my $ind2 = shift @_;
	my %map2;
	
	while ( my ($key,$value) = each %map)
	{
		my $key1 = $ind1.".".$key;
		my $value1 = ($value eq "-1") ? -1 : $ind2.".".$value;
		$map2{$key1} = $value1;
	}	
	return %map2;
}

sub extendCorrespondenceHash
{
	my %mapf = %{shift @_};
	my %mapr = %{shift @_};

	my $reac = shift @_; # should be a combined structure graph of patterns
	my $prod = shift @_;
	
	my @reac_nodelist = @{$reac->{'NodeList'}};
	my @prod_nodelist = @{$prod->{'NodeList'}};

	# filter the component states on both sides
	# find the corresponding component on the other side
	# see if it has a matching component state 
	
	my @reac_compstates = hasType($reac->{'NodeList'},'CompState');
	my @prod_compstates = hasType($prod->{'NodeList'},'CompState');
	foreach my $node(@reac_compstates)
	{
		my $reac_id = $node->{'ID'};
		my $reac_parent = ${$node->{'Parents'}}[0];
		my $prod_parent = $mapf{$reac_parent};
		if ($mapf{$reac_parent} ne "-1")
		{
			my $prod_parent = $mapf{$reac_parent};
			my $prod_id = $prod_parent.".0";
			my $node2 = findNode(\@prod_compstates,$prod_id); 
			#$node2 always exists, because we check that $mapf{...} has not returned -1
			if ($node->{'Name'} eq $node2->{'Name'})
					{
						$mapf{$reac_id} = $prod_id;
						$mapr{$prod_id} = $reac_id;
					}
		}
	}
	
	# filter the bond states on both sides
	my @reac_bondstates = hasType($reac->{'NodeList'},'BondState');
	my @prod_bondstates = hasType($prod->{'NodeList'},'BondState');
	foreach my $node (@reac_bondstates)
	{
		my $reac_id = $node->{'ID'};
		my $name = $node->{'Name'};
		my @reac_parents = @{$node->{'Parents'}};
		if (scalar @reac_parents == 1)
		{
			my $reac_parent =$reac_parents[0];
			if ($mapf{$reac_parent} ne "-1")
				{
					my $prod_parent = $mapf{$reac_parent};
					my @node2 = hasParent(\@prod_bondstates,$prod_parent);
					if (@node2 and $node2[0]->{'Name'} eq $name)
					{
						my $prod_id = $node2[0]->{'ID'};
						$mapf{$reac_id} = $prod_id;
						$mapr{$prod_id} = $reac_id;
					}
				}
		}
		elsif (scalar @reac_parents == 2)
		{
			if ($mapf{$reac_parents[0]} ne "-1" and $mapf{$reac_parents[0]} ne "-1")
				{
				my @prod_parents = sort map ( $mapf{$_}, @reac_parents);
				my @node2 = hasParents(\@prod_bondstates,\@prod_parents);
				if (@node2 and $node2[0]->{'Name'} eq $name)
					{
						my $prod_id = $node2[0]->{'ID'};
						$mapf{$reac_id} = $prod_id;
						$mapr{$prod_id} = $reac_id;
					}
				}
		}	
	}
	
	# fill out the assignments for the remaining nodes that were not assigned
	foreach my $node (@reac_nodelist)
	{
		if (! $mapf{$node->{'ID'}}) { $mapf{$node->{'ID'}} = "-1";}	
	}
	foreach my $node (@prod_nodelist)
	{
		if (! $mapr{$node->{'ID'}}) { $mapr{$node->{'ID'}} = "-1";}	
	}
	return (\%mapf,\%mapr);
}	

sub toGML_yED
{
	my $sg = shift @_;
	#this is a structure graph.
	# could be pattern, rule or combination of rules
	my $type = $sg->{'Type'};
	my @nodelist = @{$sg->{'NodeList'}};
	
	# remap all the ids to integers
	my @idlist = map {$_->{'ID'}} @nodelist;
	my %indhash = indexHash(\@idlist);
	foreach my $node (@nodelist) { remapIDs($node,\%indhash); }
	
	
	# need hashes for isGroup, gid, type, fill
	# node [ id 0 label "A" graphics [ type "roundrectangle" fill "#FFCC00" ] gid 1 isGroup 1]
	# eventually move to importing customized hashes for visual properties
	my %shape = ( 'Mol'=>'rectangle', 'Comp'=>'rectangle', 'CompState'=>'roundrectangle', 'BondState'=>'ellipse', 'GraphOp'=>'hexagon');
	my %fill = ('Mol'=>'#D2D2D2', 'Comp'=>'#FFFFFF', 'CompState'=>'#FFCC00', 'BondState'=>'#FFCC00','GraphOp'=>'#CC99FF');
	my @structnodes = grep ( { $_->{'Type'} ne 'BondState' and $_->{'Type'} ne 'GraphOp'} @nodelist);
	my @bondnodes = grep ( { $_->{'Type'} eq 'BondState' } @nodelist);
	my @graphopnodes = grep ( { $_->{'Type'} eq 'GraphOp'} @nodelist);
	
	# hashes for is group and gid
	my %isgroup;
	my %gid;
	#foreach my $node(@structnodes) { $isgroup{$node->{'ID'}} = 0;}
	foreach my $node(@structnodes) 
	{
		foreach my $parent_id(@{$node->{'Parents'}}) 
		{
			$isgroup{$parent_id} = 1; 
			$gid{$node->{'ID'}} = $parent_id; 
		}
	}
	
	foreach my $node(@graphopnodes)
	{
		if ($node->{'Name'} eq 'ChangeState' )
		{
			
			my @parents = @{$node->{'Parents'}};
			my $parent = findNode(\@nodelist,$parents[0]);
			my @grandparents = @{$parent->{'Parents'}};
			my $grandparent = $grandparents[0];
			$gid{$node->{'ID'}} = $grandparents[0]; 
		}
	}
	my @nodestrings = ();
	my @edgestrings = ();
	# make node strings
	foreach my $node(@nodelist)
	{
		# ignore if it is a bond with two parents
		if ( $node->{'Type'} eq 'BondState' and scalar @{$node->{'Parents'}} == 2) { next; }
		
		my $id = $node->{'ID'};
		my $nm = $node->{'Name'};
		my $shp = $shape{$node->{'Type'}};
		my $fl = $fill{$node->{'Type'}};
		my $string = sprintf "id %d label \"%s\" ",$id,$nm;
		$string .= sprintf "graphics [ type \"%s\" fill \"%s\" ] ",$shp,$fl;
		$string .= sprintf "LabelGraphics [ label \"%s\" anchor \"t\" ] ",$nm;
		if ($isgroup{$id}) { $string .= " isGroup 1"; }
		if (exists $gid{$id}) { $string .= sprintf " gid %d", $gid{$id};}
		$string = " node [ ".$string." ]";
		push @nodestrings, $string;
	}
	# make edges for bonds
	foreach my $node (@bondnodes)
	{
		my @parents = @{$node->{'Parents'}};
		my $source;
		my $target;
		# address wildcards
		if (scalar @parents == 1) 
		{
			$source = $node->{'ID'};
			$target = $parents[0];
		}
		# ignore bonds that are made or removed
		elsif ($node->{'Side'} eq 'both')
		{
			$source = $parents[0];
			$target = $parents[1];
		}
		else { next; }
		my $string = sprintf "source %d target %d ",$source,$target;
		$string .= "graphics [ fill \"#000000\" ] ";
		$string = " edge [ ".$string." ]";
		push @edgestrings,$string;
	}
	# make edges adjacent to graph operation nodes
	foreach my $node (@graphopnodes)
	{
		my $name = $node->{'Name'};
		my $id = $node->{'ID'};
		my @parents = @{$node->{'Parents'}};
		my @c;
		my @p;
		my @consumed;
		my @produced;
		
		if ($name eq 'ChangeState')
			{
			my @compstates = grep ( { $_->{'Type'} eq 'CompState' } @nodelist);
			my @nodes = findNodes(\@compstates,\@parents);
			@c = grep ( { $_->{'Side'} eq 'left' } @nodes);
			@p = grep ( { $_->{'Side'} eq 'right' } @nodes);
			}
			
		if ($name eq 'AddMol' or $name eq 'DeleteMol')
			{
			my @mols = grep ( { $_->{'Type'} eq 'Mol' } @nodelist);
			my @nodes = findNodes(\@mols,\@parents);
			@c = grep ( { $_->{'Side'} eq 'left' } @nodes);
			@p = grep ( { $_->{'Side'} eq 'right' } @nodes);
			}
			
		if ($name eq 'AddBond' or $name eq 'DeleteBond')
			{
				my @allbonds = grep ( { $_->{'Type'} eq 'BondState' } @nodelist);
				my $bond = findNode(\@allbonds,$parents[0]);
				my @comps = grep ( { $_->{'Type'} eq 'Comp' } @nodelist);
				my @nodes = findNodes(\@comps, $bond->{'Parents'});
				if ($name eq 'DeleteBond') { @c = @nodes; }
				if ($name eq 'AddBond') { @p = @nodes; }
			}
		
		if (@c) { @consumed = map ($_->{'ID'},@c); }
		if (@p) { @produced = map ($_->{'ID'},@p); }	
		
		foreach my $id2(@consumed)
		{
			my $string = sprintf "source %d target %d ",$id2,$id;
			$string .= "graphics [ fill \"#000000\" targetArrow \"standard\" ] ";
			$string = " edge [ ".$string." ]";
			push @edgestrings,$string;
		}
		
		foreach my $id2(@produced)
		{
			my $string = sprintf "source %d target %d ",$id,$id2;
			$string .= "graphics [ fill \"#000000\" targetArrow \"standard\" ] ";
			$string = " edge [ ".$string." ]";
			push @edgestrings,$string;
		}
	}

	my $string = "graph\n[\n hierarchic 1\n directed 1\n";
	$string .= join("\n",@nodestrings)."\n";
	$string .= join("\n",@edgestrings)."\n";
	$string .= "]\n";
	
	return $string;
}
1;
