#' Fitting Gaussian copula graphical lasso to co-occurence data
#'
#' \code{cgr} is used to fit a Gaussian copula graphical model to 
#' multivatiate discrete data, like species co-occurence data in ecology. 
#' This function fits the model and estimates the shrinkage parameter
#' using BIC. Use \code{\link{plot.cgr}} to plot the resulting graph.
#'
#' @param obj object of either class \code{\link[mvabund]{manyglm}}, 
#' or  \code{\link[mvabund]{manyany}} with ordinal models \code{\link[ordinal]{clm}}
#' @param lambda vector, values of shrinkage parameter lambda for model 
#' selection (optional, see detail)
#' @param n.lambda integer, number of lambda values 
#' for model selection (default = 100), ignored if lambda supplied
#' @param n.samp integer (default = 500), number of sets residuals used for importance sampling 
#' (optional, see detail)
#' @param method method for selecting shrinkage parameter lambda, either "BIC" (default) or "AIC"
#' @param seed integer (default = 1), seed for random number generation (optional, see detail)
#' @section Details:
#' \code{cgr} is used to fit a Gaussian copula graphical model to multivariate discrete data, such as co-occurence (multi species) data in ecology. The model is estimated using importance sampling with \code{n.samp} sets of randomised quantile or "Dunn-Smyth" residuals (Dunn & Smyth 1996), and the \code{\link{glasso}} package for fitting Gaussian graphical models. Models are fit for a path of values of the shrinkage parameter \code{lambda} chosen so that both completely dense and sparse models are fit. The \code{lambda} value for the \code{best_graph} is chosen by BIC (default) or AIC.  The seed is controlled so that models with the same data and different predictors can be compared.  
#' @return Three objects are returned; 
#' \code{best_graph} is a list with parameters for the 'best' graphical model, chosen by the chosen \code{method}; 
#' \code{all_graphs} is a list with likelihood, BIC and AIC for all models along lambda path; 
#' \code{obj} is the input object.
#' @section Author(s):
#' Gordana Popovic <g.popovic@unsw.edu.au>.
#' @section References:
#' Dunn, P.K., & Smyth, G.K. (1996). Randomized quantile residuals. Journal of Computational and Graphical Statistics 5, 236-244.
#' 
#' Popovic, G. C., Hui, F. K., & Warton, D. I. (2018). A general algorithm for covariance modeling of discrete data. Journal of Multivariate Analysis, 165, 86-100.
#' @section See also:
#' \code{\link{plot.cgr}}
#' @examples
#' library(mvabund)
#' data(spider)
#' X <- as.data.frame(spider$x)
#' abund <- spider$abund
#' spider_mod <- stackedsdm(abund,~1, data = X) 
#' spid_graph=cgr(spider_mod)
#' plot(spid_graph,pad=1)
#' @import mvabund
#' @export 
cgr <- function(obj, lambda = NULL, n.lambda = 100, 
                  n.samp = 500, method="BIC", seed = NULL) {
    
  # code chunk from simulate.lm to select seed
    if (!exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) 
      runif(1)
    if (is.null(seed)) { 
      RNGstate <- get(".Random.seed", envir = .GlobalEnv)
    } else {
      R.seed <- get(".Random.seed", envir = .GlobalEnv)
      set.seed(seed)
      RNGstate <- structure(seed, kind = as.list(RNGkind()))
      on.exit(assign(".Random.seed", R.seed, envir = .GlobalEnv))
    }
  
    if (floor(n.samp) != ceiling(n.samp)) 
        stop("n.samp must be an integer")
    
    if (floor(n.lambda) != ceiling(n.lambda)) 
        stop("n.lambda must be an integer")
    
    if (!(is.numeric(lambda) | is.null(lambda))) 
        stop("lambda must be numeric")
    
    if (!is.null(lambda)) 
        warning(" 'best' model selected among supplied lambda only")
    
    if (any(lambda < 0)) 
        stop("lambda must be non negative")
    
    if (!class(obj)[1] %in% c("manyany", "manyglm","manylm","stackedsdm")) 
        stop("please supply an manyglm, manylm, manyany or stackedsdm object")
    
    if (class(obj)[1] == "manyany" & class(obj)[2] != "clm")
        warning("cgr function is only tested on manyany with clm or tweedie")
    
    # always same result unless specified otherwise
    set.seed(seed)
    
    # simulate full set of residulas n.samp times
    res = simulate.res.S(obj, n.res = n.samp)
    
    #this chunk of code finds a path of lambda values to 
    #explore graphs ranging from completely sparse to completely dense.
    if (is.null(lambda)) {
        # starting values for log10 lambda
        current = seq(-6, 2, length.out = 10)
        
        # proportion of non-zero cond indep
        sparse_fits = full.graph.many(obj, c(0,10^current), res)
        k.frac=sparse_fits$k.frac
        
        # which lambdas give full and empty matrices
        new.min = max(which(k.frac == 1))
        new.max = min(which(k.frac == 0))
        
        # now a small sequence of lambda values, between the two
        lambda = c(0,10^seq(current[new.min], current[new.max], length.out = 10))
        sparse_fits = full.graph.many(obj, lambda, res)
        
        
        #then find the sweet spot by removing the 5 largest of the 10 values above
        if(method=="BIC"){
          sub_lam=lambda[sparse_fits$BIC<kth_largest(sparse_fits$BIC,5)]
        }else if (method=="AIC"){
          sub_lam=lambda[sparse_fits$AIC<kth_largest(sparse_fits$AIC,5)]
        }else{
          stop("lambda selection method can only be \"AIC\" or \"BIC\" ")
        }
        
        # now a larger sequence but just between those
        min_lam=min(sub_lam)
        if(min_lam>0){
          lambda = 10^c( seq(log10(min_lam), log10(max(sub_lam)), length.out = n.lambda))
        } else{
          min_lam=min(sub_lam[sub_lam>0])
          lambda = c(0,10^c( seq(log10(min_lam), log10(max(sub_lam)), length.out = (n.lambda-1))))
        }

    } else {
        n.lambda = length(lambda)
    }

    
    ag = full.graph.many(obj, lambda, res)
    k.frac = ag$k.frac
    BIC.graph = ag$BIC
    AIC.graph = ag$AIC
    logL = ag$logL
    
    #determine best graph by BIC
    if(method=="BIC"){
      best = min(which(BIC.graph == min(BIC.graph)))
    }else if (method=="AIC"){
      best = min(which(AIC.graph == min(AIC.graph)))
    }else{
      stop("lambda selection method can only be \"AIC\" or \"BIC\" ")
    }
    
    
    # find raw correlation matrix by averaging over unweighted residuals
    P = dim(res$S.list[[1]])[1]
    array.S = array(unlist(res$S.list), c(P, P, n.samp))
    precov = cov2cor(apply(array.S, c(1, 2), mean))
    colnames(precov)=rownames(precov)=colnames(obj$y)
    
    if(any(class(obj) == "manyany")){
      labs <- names(obj$params)
    }else{
      labs <- colnames(obj$y)
    }
    
    Th.best = ag$Th.out[[best]]
    Sig.best = ag$Sig.out[[best]]
    colnames(Th.best)=rownames(Th.best)=colnames(Sig.best)=rownames(Sig.best)=labs
    part_cor = -cov2cor(Th.best)
    g<-graph_from_partial(part_cor)
    #outputs
    
    graph.out = as.matrix((Th.best != 0) * 1)
    best.graph = list(graph = graph.out, prec = Th.best, cov = Sig.best, part=part_cor, Y = obj$y, logL = logL[[best]], 
        sparsity = k.frac[best],igraph_out=g)
    all.graphs = list(lambda.opt = lambda[best], logL = logL, BIC = BIC.graph, 
                      AIC = AIC.graph, lambda = lambda, k.frac = k.frac)
    raw <- list(cov=precov)
    out = list(best_graph = best.graph,raw=raw, all_graphs = all.graphs, obj = obj)
    class(out) = "cgr"
    return(out)
    
}
