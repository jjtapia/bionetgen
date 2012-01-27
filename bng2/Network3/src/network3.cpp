/*
 * network3.cpp
 *
 *  Created on: Jul 30, 2011
 *      Author: Leonard Harris
 */

#include "network3.hh"
#include "util/util.hh"

vector<SimpleSpecies*> Network3::SPECIES;
vector<pair<Observable*,double> > Network3::OBSERVABLE;
vector<pair<Function*,double> > Network3::FUNCTION;
vector<Reaction*> Network3::REACTION;
PLA* Network3::PLA_SIM = NULL;

void Network3::init_Network3(bool verbose){
	//
	cout << "*** Initializing Network3 ***" << endl;
	//
	// SPECIES
	if (verbose){
		cout << "------------\nSPECIES\n------------\n";
	}
//	vector<SimpleSpecies*> SPECIES;
	vector<bool> fixed;
    {
		Elt* elt = network.species->list;
		for (int i=0;i < network.species->n_elt;i++){
			SPECIES.push_back(new SimpleSpecies(elt->name,floor(elt->val+0.5)));
			fixed.push_back(elt->fixed);
			if (verbose) cout << SPECIES[i]->name << "\t" << SPECIES[i]->population << endl;
			elt = elt->next;
		}
    }
//  if (verbose) cout << endl;
    //
    // OBSERVABLES
    if (verbose) cout << "------------\nOBSERVABLES\n------------\n";
//    vector<pair<Observable*,double> > OBSERVABLE;
    {
		Group* grp = network.spec_groups;
		vector<SimpleSpecies*> sp;
		vector<double> mult;
		int off = network.species->offset;
		for (int i=0;i < network.n_groups;i++){
			sp.clear(); mult.clear();
			for (int j=0;j < grp->n_elt;j++){
				sp.push_back(SPECIES.at(grp->elt_index[j]-off));
				mult.push_back(grp->elt_factor[j]);
			}
			OBSERVABLE.push_back(pair<Observable*,double>(new Observable(grp->name,sp,mult),0.0));
			OBSERVABLE[i].second = OBSERVABLE[i].first->getValue();
			//
			if (verbose) cout << OBSERVABLE[i].first->toString() << endl;
			//
			grp = grp->next;
		}
    }
//  if (verbose) cout << endl;
	//
	// FUNCTIONS
    if (verbose) cout << "------------\nFUNCTIONS\n------------\n";
//	vector<pair<Function*,double> > FUNCTION;
	{
    	int off = network.species->offset;
		for (unsigned int i=0;i < network.functions.size();i++){
//			cout << network.functions[i].GetExpr() << "= " << network.functions[i].Eval() << "\t";
			//
			FUNCTION.push_back(pair<Function*,double>(new Function(network.rates->elt[network.var_parameters[i]-off]->name),0.0));
			//
			map<string,double*> var = network.functions[i].GetUsedVar();
			map<string,double*>::iterator iter;
//			for (iter = var.begin();iter != var.end();iter++){
//				cout << "{" << (*iter).first << " = " << *(*iter).second << "}\t";
//			}
//			cout << endl;
			// Search observables
			for (unsigned int j=0;j < OBSERVABLE.size();j++){
				if (var.find(OBSERVABLE[j].first->name) != var.end()){
//					cout << "\t" << OBSERVABLE[j].first->name << " = " << OBSERVABLE[j].second << endl;
					FUNCTION[i].first->p->DefineVar(OBSERVABLE[j].first->name,&OBSERVABLE[j].second);
				}
			}
			// Search parameters
			for (Elt* elt=network.rates->list;elt != NULL;elt=elt->next){
				if (var.find(elt->name) != var.end()){
//					cout << "\t" << "rates[" << elt->index << "] = " << elt->name << " (";
					bool func = false;
					// Is it a function?
					for (unsigned int j=0;j < network.var_parameters.size() && !func;j++){
						if (elt->index == network.var_parameters[j]){
							// YES
//							cout << "function[" << j <<"] = " << network.functions[j].GetExpr() << ")" << endl;
							func = true;
							bool found = false;
							// Which one?
							for (unsigned int k=0;k < FUNCTION.size() && !found;k++){
								if (network.functions[j].GetExpr() == FUNCTION[k].first->GetExpr()){
									found = true;
									FUNCTION[i].first->p->DefineVar(elt->name,&FUNCTION[k].second);
								}
							}
							// Error check
							if (!found){
								cout << "Error in Network3::init_Network3(): Couldn't find function "
									 << network.functions[j].GetExpr() << ". Exiting." << endl;
								exit(1);
							}
						}
					}
					// NO, it's a constant
					if (!func){
//						cout << "constant)" << endl;
						FUNCTION[i].first->p->DefineConst(elt->name,elt->val);
					}
				}
			}
			// Set expression
			string expr = network.functions[i].GetExpr();
			expr.erase(expr.size()-1); // Trim last character (muParser adds a null to the end)
			FUNCTION[i].first->p->SetExpr(expr);
			FUNCTION[i].second = FUNCTION[i].first->Eval();
			if (verbose) cout << FUNCTION[i].first->GetExpr() << "= " << FUNCTION[i].second << endl;
		}
	}
//	if (verbose) cout << endl;
	//
    // REACTIONS
	if (verbose) cout << "------------\nREACTIONS\n------------\n";
//	vector<Reaction*> REACTION;
    {
		int off = network.species->offset;
		Rxn* rxn = network.reactions->list;
		REACTION.resize(network.reactions->n_rxn);
		//
		// Loop over reactions
		for (int i=0;i < network.reactions->n_rxn;i++){
			double fixed_factor = 1.0; // Populations of any fixed species (incorporate into rate constant)
			//
			// Collect reactants
			double n = 0.0; // for repeated species
			vector<SimpleSpecies*> re; // reactants
			vector<int> reS; // reactant stoichiometries
			for (int j=0;j < rxn->n_reactants;j++){
				if (verbose){
					if (j != 0) cout << " + ";
					cout << SPECIES.at(rxn->r_index[j]-off)->name;
				}
				// Fixed species
				if (fixed.at(rxn->r_index[j]-off)){
					if (j != 0){
						if (rxn->r_index[j] == rxn->r_index[j-1]){ // repeated species
							n += 1.0;
						}
						else{
							n = 0.0;
						}
					}
					fixed_factor *= (SPECIES.at(rxn->r_index[j]-off)->population - n) / (n + 1.0);
				}
				 // Not fixed
				else{
					re.push_back(SPECIES.at(rxn->r_index[j]-off));
					reS.push_back(-1);
				}
			}
			if (verbose) cout << " -> ";
			//
			// Collect products
			vector<SimpleSpecies*> pr; // products
			vector<int> prS; // product stoichiometries
			for (int j=0;j < rxn->n_products;j++){
				if (verbose){
					if (j != 0) cout << " + ";
					cout << SPECIES.at(rxn->p_index[j]-off)->name;
				}
				// Not a fixed species
				if(!fixed.at(rxn->p_index[j]-off)){
					pr.push_back(SPECIES.at(rxn->p_index[j]-off));
					prS.push_back(1);
				}
			}
			if (verbose) cout << endl;
/*			cout << "\t" << rxn->n_reactants << "\t" << rxn->n_products << "\t" << rxn->rateLaw_type;
			cout << "\t" << rxn->n_rateLaw_params << "\t" << rxn->stat_factor << "\t(" << rxn->rateLaw_params[0];
			for (int j=1;j < rxn->n_rateLaw_params;j++){ cout << ", " << rxn->rateLaw_params[j]; }
			cout << ")\t(" << rxn->rateLaw_indices[0];
			for (int j=1;j < rxn->n_rateLaw_params;j++){ cout << ", " << rxn->rateLaw_indices[j]; }
			cout << ")";
*/			//
			// Remove combinatorial factor from stat factor
			double path_factor = rxn->stat_factor;
			n = 1.0;
			for (int j=1;j < rxn->n_reactants;j++){
				if (SPECIES.at(rxn->r_index[j]-off) == SPECIES.at(rxn->r_index[j-1]-off)){
					n += 1.0;
				}
				else{
					n = 1.0;
				}
				path_factor *= n;
			}
//			cout << "\t" << "stat_factor = " << rxn->stat_factor << "\t" <<  "path_factor = " << path_factor << endl;
			//
			// Build reaction
			if (rxn->rateLaw_type == ELEMENTARY){
				if (verbose) cout << "]]] Elementary rxn type [[[" << endl;
				// Error check
				if (rxn->n_rateLaw_params < 1){
					cout << "Error in Network3::init_Network3(): Elementary rxns must have at least 1 parameter. You have "
						 << rxn->n_rateLaw_params << ". Exiting." << endl;
					exit(1);
				}
				//
				double c = fixed_factor*path_factor*rxn->rateLaw_params[0];
				REACTION.at(i) = new ElementaryRxn(c,re,reS,pr,prS);
				if (verbose) cout << REACTION.at(i)->toString() << endl << endl;
			}
			else if (rxn->rateLaw_type == SATURATION){
				if (verbose) cout << "]]] Saturation rxn type [[[" << endl;
				// Error check
				if (rxn->n_rateLaw_params < 1){
					cout << "Error in Network3::init_Network3(): Saturation rxns must have at least 1 parameter. You have "
						 << rxn->n_rateLaw_params << ". Exiting." << endl;
					exit(1);
				}
				//
				double kcat = fixed_factor*path_factor*rxn->rateLaw_params[0];
				vector<double> Km;
				for (int j=1;j < rxn->n_rateLaw_params;j++){
					Km.push_back(rxn->rateLaw_params[j]);
				}
				REACTION.at(i) = new SaturationRxn(kcat,Km,re,reS,pr,prS);
				if (verbose) cout << REACTION.at(i)->toString() << endl << endl;
			}
			else if (rxn->rateLaw_type == MICHAELIS_MENTEN){
				if (verbose) cout << "]]] Michaelis-Menten rxn type [[[" << endl;
				// Error check
				if (rxn->n_rateLaw_params != 2){
					cout << "Error in Network3::init_Network3(): Michaelis-Menten rxns must have exactly 2 parameters. You have "
						 << rxn->n_rateLaw_params << ". Exiting." << endl;
					exit(1);
				}
				//
				double kcat = fixed_factor*path_factor*rxn->rateLaw_params[0];
				double Km = rxn->rateLaw_params[1];
				REACTION.at(i) = new MichaelisMentenRxn(kcat,Km,re,reS,pr,prS);
				if (verbose) cout << REACTION.at(i)->toString() << endl << endl;
			}
			else if (rxn->rateLaw_type == HILL){
				if (verbose) cout << "]]] Hill rxn type [[[" << endl;
				// Error check
				if (rxn->n_rateLaw_params != 3){
					cout << "Error in Network3::init_Network3(): Hill rxns must have exactly 3 parameters. You have "
						 << rxn->n_rateLaw_params << ". Exiting." << endl;
					exit(1);
				}
				//
				double k = fixed_factor*path_factor*rxn->rateLaw_params[0];
				double Kh = rxn->rateLaw_params[1];
				double h = rxn->rateLaw_params[2];
				REACTION.at(i) = new HillRxn(k,Kh,h,re,reS,pr,prS);
				if (verbose) cout << REACTION.at(i)->toString() << endl << endl;
			}
			else if (rxn->rateLaw_type == FUNCTIONAL){
				if (verbose) cout << "]]] Function rxn type [[[" << endl;
				// Find the function
				unsigned int func_index;
				for (unsigned int j=0;j < network.var_parameters.size();j++){
					if (network.var_parameters[j] == rxn->rateLaw_indices[0]){
						func_index = j;
						break;
					}
				}
				// Prepend path_factor to parser expression and reset expression
				string new_expr = Util::toString(fixed_factor) + "*" + Util::toString(path_factor) + "*"
						+ FUNCTION[func_index].first->GetExpr();
				new_expr.erase(new_expr.size()-1); // Erase Null character appended to expression by muParser
				FUNCTION[func_index].first->p->SetExpr(new_expr);
				FUNCTION[func_index].second = FUNCTION[func_index].first->Eval();
				REACTION.at(i) = new FunctionalRxn(FUNCTION[func_index].first,re,reS,pr,prS);
				if (verbose) cout << REACTION.at(i)->toString() << endl << endl;
			}
			else{
				cout << "Error in Network3::init_Network3(): Rate law type for reaction " << rxn->index
					 << " not recognized (Type " << rxn->rateLaw_type << "). Exiting." << endl;
				exit(1);
			}
			//
			rxn = rxn->next;
		}
    }
}

void Network3::init_PLA(string config, bool verbose){

	// 1st argument: Method type (fEuler, midpt, rk4, grk).
	// 2nd argument: Rxn-based (rb) or species-based (sb).
	// 3rd argument: PLA config (tc:fg:pl, tc:fg_pl, tc_fg_pl).
	// 4th argument: PLA parameters:
	//				 Minimum of 4 (eps,approx1,gg1,p).
	//				 Optional 3 additional (pp,q,w).
	// 5th argument (optional): Path to butcher tableau file (required if 'grk' chosen in arg 1).

	cout << "Initializing PLA simulation. Configuration = " << config << endl;

	// Error check
	if (config[0] == '|'){
		cout << "Error in Network3::init_PLA(): A '|' cannot be the first character of the configuration string. Exiting." << endl;
		cout << "\t" << "PLA_config: " + config << endl;
		exit(1);
	}
	if (config[config.size()-1] == '|'){
		cout << "Error in Network3::init_PLA(): A '|' cannot be the last character of the configuration string. Exiting." << endl;
		cout << "\t" << "PLA_config: " + config << endl;
		exit(1);
	}

	// Elements
	vector<vector<double> > alpha; 	// Butcher tableau
	vector<double> beta;			// Butcher tableau
	vector<double> param;			// PLA parameters (eps,approx1,gg1,etc.)
	TauCalculator* tc = NULL;
	RxnClassifier* rc = NULL;
	FiringGenerator* fg = NULL;
	PostleapChecker* pl = NULL;

	// Collect arguments
	vector<string> arg;
	int last = -1;
	int next;
	while ((next = config.find('|',last+1)) != (int)string::npos){
		arg.push_back(config.substr(last+1,next-(last+1)));
		last = next;
//		cout << arg[arg.size()-1] << endl;
	}
	arg.push_back(config.substr(last+1,config.size()-(last+1))); // Get last argument
//	cout << arg[arg.size()-1] << endl;

	// Error check
	if (arg.size() != 4 && arg.size() != 5){
		cout << "Error in Network3::init_PLA(): A minimum of 4 arguments are required, and a maximum of 5 are allowed. ";
		cout << "You have " << arg.size() << ". Exiting." << endl;
		exit(1);
	}
	cout << "Read " << arg.size() << " arguments." << endl;

	// Process arguments
	if (verbose) cout << "Processing..." << endl;

	// Argument 1: Method type
	if (arg[0] == "fEuler"){
		if (verbose) cout << "1: You've chosen 'fEuler', very good." << endl;
		// alpha
		alpha.resize(1);
		alpha[0].push_back(0.0);
		// beta
		beta.push_back(1.0);
	}
	else if (arg[0] == "midpt"){
		if (verbose) cout << "1: You've chosen 'midpt', this should be interesting." << endl;
		// alpha
		alpha.resize(2);
		alpha[0].push_back(0.0); alpha[0].push_back(0.0);
		alpha[1].push_back(0.5); alpha[1].push_back(0.0);
		// beta
		beta.push_back(0.0); beta.push_back(1.0);
	}
	else if (arg[0] == "rk4"){
		if (verbose) cout << "1: You've chosen 'rk4', go get 'em cowboy." << endl;
		// alpha
		alpha.resize(4);
		alpha[0].push_back(0.0); alpha[0].push_back(0.0); alpha[0].push_back(0.0); alpha[0].push_back(0.0);
		alpha[1].push_back(0.5); alpha[1].push_back(0.0); alpha[1].push_back(0.0); alpha[1].push_back(0.0);
		alpha[2].push_back(0.0); alpha[2].push_back(0.5); alpha[2].push_back(0.0); alpha[2].push_back(0.0);
		alpha[3].push_back(0.0); alpha[3].push_back(0.0); alpha[3].push_back(1.0); alpha[3].push_back(0.0);
		// beta
		beta.push_back(1.0/6.0); beta.push_back(1.0/3.0); beta.push_back(1.0/3.0); beta.push_back(1.0/6.0);
	}
	else if (arg[0] == "grk"){
		// Error check
		if (arg.size() != 5){
			cout << "Error in Network3::init_PLA(): You've chosen the general Runge-Kutta option ('grk') but you haven't" << endl;
			cout << "provided the path and name of the file containing your Butcher tableau. Please try again. Exiting." << endl;
			exit(1);
		}
		if (verbose) cout << "1: You've chosen 'grk', the adventurous type I see." << endl;
		if (arg.size() < 5){
			cout << "Uh oh, you've chosen 'grk' but I can't identify your Butcher tableau input file. It should be the" << endl;
			cout << "5th argument but I only see " << arg.size() << " arguments. Please try again. Exiting." << endl;
		}
	}
	else{
		cout << "Error in Network3::init_PLA(): Didn't recognize your choice of method. Currently supported methods are " << endl;
		cout << "'fEuler', 'midpt', 'rk4' and 'grk' (general Runge-Kutta). Please try again. Exiting." << endl;
		exit(1);
	}

	// Argument 2: RB or SB
	if (arg[1] == "rb" || arg[1] == "RB"){
		if (verbose) cout << "2: You've chosen a reaction-based approach. Oh to be young again." << endl;
	}
	else if (arg[1] == "sb" || arg[1] == "SB"){
		if (verbose) cout << "2: You've chosen a species-based approach. Excellent choice sir." << endl;
	}
	else{
		cout << "Error in Network3::init_PLA(): The 2nd argument must specify rxn-based ('rb' or 'RB') ";
		cout << "or species-based ('sb' or 'SB')." << endl;
		cout << "You entered '" << arg[1] << "'. Please try again. Exiting." << endl;
		exit(1);
	}

	// Argument 3: PLA configuration
	if (arg[2] == "tc:fg:pl"){
		if (verbose){
			cout << "3: You've chosen to use a preleap tau calculator and a negative-population postleap checker." << endl;
			cout << "   Very good, a straightforward but effective choice." << endl;
		}
	}
	else if (arg[2] == "tc:fg_pl"){
		if (verbose){
			cout << "3: You've chosen to use a preleap tau calculator along with a combined firing generator/postleap checker.\n";
			cout << "   Very interesting, this should improve the accuracy of your results." << endl;
		}
	}
	else if (arg[2] == "tc_fg_pl"){
		if (verbose){
			cout << "3: Ahh, you must be hungry, you've chosen the combo meal: the combined" << endl;
			cout << "   tau calculator/firing generator/postleap checker. I like how you think." << endl;
		}
	}
	else{
		cout << "Error in Network3::init_PLA(): Can't understand the combination of PLA elements that you've entered (";
		cout << arg[2] << "). Exiting." << endl;
		exit(1);
	}

	// Argument 4: PLA parameters
	last = -1;
	while ((next = arg[3].find(',',last+1)) != (int)string::npos){
		param.push_back(atof(arg[3].substr(last+1,next-(last+1)).c_str()));
		last = next;
//		cout << param[param.size()-1] << endl;
	}
	param.push_back(atof(arg[3].substr(last+1,arg[3].size()-(last+1)).c_str())); // Get last parameter
//	cout << param[param.size()-1] << endl;
	if (verbose){
		cout << "4: You've specified " << param.size() << " parameters:" << endl;
		for (unsigned int i=0;i < param.size();i++){
			if (i==0) cout << "   eps = "		<< param[0] << endl;
			if (i==1) cout << "   approx1 = " 	<< param[1] << endl;
			if (i==2) cout << "   gg1 = " 	 	<< param[2] << endl;
			if (i==3) cout << "   p = " 	 	<< param[3] << endl;
			if (i==4) cout << "   pp = " 	 	<< param[4] << endl;
			if (i==5) cout << "   q = " 	 	<< param[5] << endl;
			if (i==6) cout << "   w = " 		<< param[6] << endl;
		}
	}
	// Error check
	if (param.size() < 4 || param.size() > 7){
		cout << "Oops, minimum number of parameters is 4 and maximum is 7. You've specified " << param.size() << "." << endl;
		cout << "Please try again. Exiting." << endl;
		exit(1);
	}
	if (arg[2] == "tc_fg_pl" && param.size() < 7){
		cout << "Oops, you've selected the '" << arg[2] << "' configuration which requires 7 parameters." << endl;
		cout << "You've specified " << param.size() << ". Please try again. Exiting." << endl;
		exit(1);
	}

	// Argument 5 (optional): Path to Butcher tableau file
	FILE* bt_file = NULL;
	if (arg.size() == 5){
		if (verbose) cout << "5: You've specified a Butcher tableau input file: " << arg[4] << endl;

		// Continue
		if (arg[0] != "grk"){ // skip
			if (verbose) cout << "   You haven't chosen 'grk', so I'll ignore it." << endl;
		}
		else{

			// Try to open the file
			if ((bt_file = fopen(arg[4].c_str(),"r"))){
				if (verbose) cout << "   Ok, I see it." << endl;
			}
			else{
				cout << "   Sorry , I can't find your Butcher tableau input file \"" << arg[4].c_str()
				     << "\". Please try again. Exiting." << endl;
				exit(1);
			}

			// Add a row to alpha matrix (Butcher tableau)
			alpha.push_back(vector<double>());

			// Read from file
			ifstream strm(arg[4].c_str(),ifstream::in);
			string s;
			double x;
			char c;
			unsigned int dim = 0;
			unsigned int nColumns = 0;
			unsigned int nRows = 0;
			bool foundDim = false;
			while (!strm.eof()){
				s.clear();
				strm >> s;
				if (s.size() != 0){ // skip blank lines
					int div = s.find('/');
					if (div != (int)string::npos){
						double num = atof(s.substr(0,div).c_str());
						double denom = atof(s.substr(div+1,s.size()-(div+1)).c_str());
						x = num/denom;
//						cout << "(=" << (num/denom) << ")";
//						cout << "(=" << num << "/" << denom << ")";
//						cout << "(=" << x.substr(0,found) << "/" << x.substr(found+1,x.size()-(found+1)) << ")";
					}
					else{
						x = atof(s.c_str());
					}
//					cout << x << ",";
					if (foundDim && nRows == dim){ // beta value (nRows is # of *completed* rows, not current row)
						beta.push_back(x);
					}
					else{ // alpha value
						alpha[alpha.size()-1].push_back(x);
					}
					//
					nColumns++;
					if (!foundDim) dim++;
					c = strm.peek();
					while (c == ' ' || c == '\t'){
						strm.get();
						c = strm.peek();
					}
					if (c == '\n' || c == EOF){
//						cout << "\n";
						if (foundDim && nColumns != dim){
							cout << "Error in Network3::initPLA(): Line " << (nRows+1) << " of " << arg[4] << " has " << nColumns
								 << " columns." << endl;
							cout << "Already read " << dim << " entries in line 1. Butcher tableau must be square. Exiting." << endl;
							exit(1);
						}
						nRows++;
						nColumns = 0;
						foundDim = true;
						if (c == '\n' && nRows < dim){
							alpha.push_back(vector<double>());
						}
					}
					else{
//						cout << "\t";
					}
				}
			}
			// Print to screen
			if (verbose){
				cout << "   -----" << endl;
				cout << "   Columns:\t" << dim << endl;
				cout << "   Rows:\t" << nRows << endl;
				cout << "   -----" << endl;
				for (unsigned int i=0;i < alpha.size();i++){
					cout << "   ";
					for (unsigned int j=0;j < alpha[i].size();j++){
						cout << alpha[i][j] << "\t";
					}
					cout << endl;
				}
				cout << "   -----" << endl;
				cout << "   ";
				for (unsigned int i=0;i < beta.size();i++){
					cout << beta[i] << "\t";
				}
				cout << endl;
			}
		}
	}

	// Build the PLA simulator
	ButcherTableau bt(alpha,beta);
	double eps = param[0];
	double approx1 = param[1];
	double gg1 = param[2];
	double p = param[3];
	//
	// Preleap TC (required for all configurations)
	Preleap_TC* ptc;
	if (arg[1] == "rb" || arg[1] == "RB"){
		static fEulerPreleapRB_TC fe_ptc(eps,REACTION);
		ptc = &fe_ptc;
	}
	else{
		static fEulerPreleapSB_TC fe_ptc(eps,SPECIES,REACTION);
		ptc = &fe_ptc;
	}
	//
	// Configuration 1: Preleap TC, Runge-Kutta RC_FG, NegPop PL
	if (arg[2] == "tc:fg:pl"){
		// TC
		tc = ptc;
		// RC_FG
		static eRungeKutta_RC_FG erk_rc_fg(bt,approx1,gg1,SPECIES,REACTION);
		rc = &erk_rc_fg; fg = &erk_rc_fg;
		// PL
		static NegPop_PL neg_pl(p,SPECIES,REACTION);
		pl = &neg_pl;
	}
	//
	// Configuration 2: Preleap TC, Runge-Kutta RC_FG_PL
	if (arg[2] == "tc:fg_pl"){
		// TC
		tc = ptc;
		// RC_FG_PL
		if (arg[1] == "rb" || arg[1] == "RB"){
			static eRungeKuttaRB_RC_FG_PL erk_rc_fg_pl(bt,eps,p,approx1,gg1,SPECIES,REACTION);
			rc = &erk_rc_fg_pl;	fg = &erk_rc_fg_pl;	pl = &erk_rc_fg_pl;
		}
		else{
			static eRungeKuttaSB_RC_FG_PL erk_rc_fg_pl(bt,eps,p,approx1,gg1,SPECIES,REACTION);
			rc = &erk_rc_fg_pl;	fg = &erk_rc_fg_pl;	pl = &erk_rc_fg_pl;
		}
	}
	//
	// Configuration 3: Combined Runge-Kutta TC_RC_FG_PL
	if (arg[2] == "tc_fg_pl"){
		double pp = param[4];
		double q = param[5];
		double w = param[6];
		if (arg[1] == "rb" || arg[1] == "RB"){
			static eRungeKuttaRB_TC_RC_FG_PL erk_tc_rc_fg_pl(bt,eps,approx1,gg1,p,pp,q,w,SPECIES,REACTION,*ptc);
			tc = &erk_tc_rc_fg_pl; rc = &erk_tc_rc_fg_pl; fg = &erk_tc_rc_fg_pl; pl = &erk_tc_rc_fg_pl;
		}
		else{
			static eRungeKuttaSB_TC_RC_FG_PL erk_tc_rc_fg_pl(bt,eps,approx1,gg1,p,pp,q,w,SPECIES,REACTION,*ptc);
			tc = &erk_tc_rc_fg_pl; rc = &erk_tc_rc_fg_pl; fg = &erk_tc_rc_fg_pl; pl = &erk_tc_rc_fg_pl;
		}
	}
	//
	PLA_SIM = new PLA(*tc,*rc,*fg,*pl,SPECIES,REACTION);
	if (verbose) cout << "...Ok done, let's go for it." << endl;
}

void Network3::run_PLA(double tStart, double maxTime, double sampleTime, long maxSteps, long stepInterval,
		char* prefix, bool verbose){

	// Error check
	if ((maxTime-tStart) < 0.0){
		cout << "Error in Network3::run_PLA(): Simulation time cannot be negative. Exiting." << endl;
		exit(1);
	}
	if (sampleTime < 0.0){
		cout << "Error in Network3::run_PLA(): Sampling time cannot be negative. Exiting." << endl;
		exit(1);
	}
	if (maxSteps < 0){
		cout << "Warning in Network3::run_PLA(): 'maxSteps' is negative (" << maxSteps << "). Simulation won't run." << endl;
	}

	// Species file (must exist)
	FILE* cdat = NULL;
	string cFile(prefix);
	cFile += ".cdat";
//	cout << cFile;
	if ((cdat = fopen(cFile.c_str(),"r"))){
//		cout << " exists." << endl;
		fclose(cdat);
		cdat = fopen(cFile.c_str(),"a");
	}
	else {
		cout << "Error in Network3::run_PLA(): Concentrations file \"" << cFile << "\" doesn't exist. Exiting." << endl;
		exit(1);
	}
	//
	// Observables file (optional)
	FILE* gdat = NULL;
	string gFile(prefix);
	gFile += ".gdat";
//	cout << gFile;
	if ((gdat = fopen(gFile.c_str(),"r"))){
//		cout << " exists." << endl;
		fclose(gdat);
		gdat = fopen(gFile.c_str(),"a");
	}
	else{
		cout << "Warning: Groups file \"" << gFile << "\" doesn't exist." << endl;
	}
	//
	// Functions file (optional)
	FILE* fdat = NULL;
	string fFile(prefix);
	fFile += ".fdat";
//	cout << fFile;
	if ((fdat = fopen(fFile.c_str(),"r"))){
//		cout << " exists." << endl;
		fclose(fdat);
		fdat = fopen(fFile.c_str(),"a");
	}
	else{
		cout << "Warning: Functions file \"" << fFile << "\" doesn't exist." << endl;
	}

	// Identify observables involved in functions
	vector<unsigned int> funcObs;
	for (unsigned int i=0;i < FUNCTION.size();i++){
		map<string,double*> var = FUNCTION[i].first->p->GetUsedVar();
		for (unsigned int j=0;j < OBSERVABLE.size();j++){
			if (var.find(OBSERVABLE[j].first->name) != var.end()){
				bool already = false;
				for (unsigned int k=0;k < funcObs.size() && !already;k++){
					if (funcObs[k] == j){
						already = true;
					}
				}
				if (!already){ // add to the list
					funcObs.push_back(j);
				}
			}
		}
	}

	// Prepare for simulation
	double time = tStart;
	long step = 0;
	double nextOutput = tStart + sampleTime;
	bool lastOut = true;
	if (stepInterval <= 0) stepInterval = LONG_MAX; // A negative stepInterval means infinity

	// Initial output to stdout
	if (verbose){
		cout << "#" << "\t" << setw(8) << left << "time" << "\t" << "step";
		for (unsigned int i=0;i < OBSERVABLE.size();i++){
			cout << "\t" << OBSERVABLE[i].first->name;
		}
		cout << endl;
		cout << "\t" << fixed << time; cout.unsetf(ios::fixed); cout << "\t" << step;
		for (unsigned int i=0;i < OBSERVABLE.size();i++){
			cout << "\t" << OBSERVABLE[i].second;
		}
		cout << endl;
	}

	// Simulation loop
	if (!verbose) cout << "Running..." << flush;
	while (time < maxTime && step < maxSteps && PLA_SIM->tau < INFINITY){

		// Next step
		step++;
		PLA_SIM->nextStep();
		time += PLA_SIM->tau;

		// Is it time to output?
		lastOut = false;
		if (time >= nextOutput || (step % stepInterval) == 0){ // YES
			// Update all observables
			for (unsigned int i=0;i < OBSERVABLE.size();i++){
				OBSERVABLE[i].second = OBSERVABLE[i].first->getValue();
			}
			// Update all functions
			for (unsigned int i=0;i < FUNCTION.size();i++){
				FUNCTION[i].second = FUNCTION[i].first->Eval();
			}
			//
			// Output to file
			Network3::print_species_concentrations(cdat,time);
			if (gdat) Network3::print_observable_concentrations(gdat,time);
			if (fdat) Network3::print_function_values(fdat,time);
			//
			// Output to stdout
			if (verbose){
				cout << "\t" << fixed << time; cout.unsetf(ios::fixed); cout << "\t" << step;
				for (unsigned int i=0;i < OBSERVABLE.size();i++){
					cout << "\t" << OBSERVABLE[i].second;
				}
				cout << endl;
			}
			if (time >= nextOutput) nextOutput += sampleTime;
			lastOut = true;
		}
		else{ // NO
			// Only update observables that are involved in functions
			for (unsigned int i=0;i < funcObs.size();i++){
				OBSERVABLE[funcObs[i]].second = OBSERVABLE[funcObs[i]].first->getValue();
			}
			// Update all functions
			for (unsigned int i=0;i < FUNCTION.size();i++){
				FUNCTION[i].second = FUNCTION[i].first->Eval();
			}
		}
	}

	// Final output
	if (!lastOut){
		// Update all observables
		for (unsigned int i=0;i < OBSERVABLE.size();i++){
			OBSERVABLE[i].second = OBSERVABLE[i].first->getValue();
		}
		// Update all functions
		for (unsigned int i=0;i < FUNCTION.size();i++){
			FUNCTION[i].second = FUNCTION[i].first->Eval();
		}
		//
		// Output to file
		Network3::print_species_concentrations(cdat,time);
		if (gdat) Network3::print_observable_concentrations(gdat,time);
		if (fdat) Network3::print_function_values(fdat,time);
		//
		// Output to stdout
		if (verbose){
			cout << "\t" << fixed << time; cout.unsetf(ios::fixed); cout << "\t" << step;
			for (unsigned int i=0;i < OBSERVABLE.size();i++){
				cout << "\t" << OBSERVABLE[i].second;
			}
			cout << endl;
		}
	}
	if (!verbose) cout << "Done" << endl;
	fprintf(stdout, "TOTAL STEPS: %d\n", (int)step);

	// Close files
	fclose(cdat);
	if (gdat) fclose(gdat);
	if (fdat) fclose(fdat);
}

void Network3::print_species_concentrations(FILE* out, double t){
	// Error check
	if (!out){
		cout << "Error in Network3::print_species_concentrations(): 'out' file does not exist. Exiting." << endl;
		exit(1);
	}
	//
	fprintf(out, "%19.12e", t);
	for (unsigned int i = 0;i < SPECIES.size();i++) {
		fprintf(out, " %19.12e", SPECIES[i]->population);
	}
	fprintf(out, "\n");
	fflush(out);
}

void Network3::print_observable_concentrations(FILE* out, double t){
	// Error check
	if (!out){
		cout << "Error in Network3::print_observable_concentrations(): 'out' file does not exist. Exiting." << endl;
		exit(1);
	}
	//
	const char *fmt = "%15.8e";
	fprintf(out, fmt, t);
	for (unsigned int i=0;i < OBSERVABLE.size();i++){
		fprintf(out, " ");
		fprintf(out, fmt, OBSERVABLE[i].second);
	}
	fprintf(out, "\n");
	fflush(out);
}

void Network3::print_function_values(FILE* out, double t){
	// Error check
	if (!out){
		cout << "Error in Network3::print_function_values(): 'out' file does not exist. Exiting." << endl;
		exit(1);
	}
	//
	const char *fmt = "%15.8e";
	fprintf(out, fmt, t);
	for (unsigned int i=0;i < FUNCTION.size();i++){
		fprintf(out, " ");
		fprintf(out, fmt, FUNCTION[i].second);
	}
	fprintf(out, "\n");
	fflush(out);
}

void Network3::close_Network3(bool verbose){
    for (unsigned int i=0;i < SPECIES.size();i++){
    	if (verbose) cout << "Deleting Network3::SPECIES[" << i << "]: " << SPECIES[i]->name << endl;
    	delete SPECIES[i];
    }
    for (unsigned int i=0;i < OBSERVABLE.size();i++){
    	if (verbose) cout << "Deleting Network3::OBSERVABLE[" << i << "]: " << OBSERVABLE[i].first->name << endl;
    	delete OBSERVABLE[i].first;
    }
    for (unsigned int i=0;i < FUNCTION.size();i++){
    	if (verbose) cout << "Deleting Network3::FUNCTION[" << i << "]: " << FUNCTION[i].first->name << " = "
						  << FUNCTION[i].first->GetExpr() << endl;
    	delete FUNCTION[i].first;
    }
    for (unsigned int i=0;i < REACTION.size();i++){
    	if (verbose) cout << "Deleting Network3::REACTION[" << i << "]: " << REACTION[i]->toString() << endl;
    	delete REACTION[i];
    }
    if (PLA_SIM){
    	if (verbose) cout << "Deleting Network3::PLA_SIM" << endl;
    	delete PLA_SIM;
    }
}