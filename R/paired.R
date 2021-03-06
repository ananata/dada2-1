################################################################################
#' Merge denoised forward and reverse reads.
#' 
#' This function attempts to merge each denoised pair of forward and reverse reads, 
#' rejecting any pairs which do not sufficiently overlap or which contain too many 
#' (>0 by default) mismatches in the overlap region. Note: This function assumes that 
#' the fastq files for the forward and reverse reads were in the same order.
#' 
#' @param dadaF (Required). A \code{\link{dada-class}} object, or a list of such objects.
#'  The \code{\link{dada-class}} object(s) generated by denoising the forward reads.
#' 
#' @param derepF (Required). \code{character} or \code{\link{derep-class}}.
#'  The file path(s) to the fastq file(s), or a directory containing fastq file(s) corresponding to the
#'  the forward reads of the samples to be merged. Compressed file formats such as .fastq.gz and .fastq.bz2 are supported.
#'  A \code{\link{derep-class}} object (or list thereof) returned by \code{link{derepFastq}} can also be provided.
#'  These \code{\link{derep-class}} object(s) or fastq files should correspond to those used 
#'  as input to the the \code{\link{dada}} function when denoising the forward reads.
#'  
#' @param dadaR (Required). A \code{\link{dada-class}} object, or a list of such objects.
#'  The \code{\link{dada-class}} object(s) generated by denoising the reverse reads.
#' 
#' @param derepR (Required). \code{character} or \code{\link{derep-class}}.
#'  The file path(s) to the fastq file(s), or a directory containing fastq file(s) corresponding to the
#'  the reverse reads of the samples to be merged. Compressed file formats such as .fastq.gz and .fastq.bz2 are supported.
#'  A \code{\link{derep-class}} object (or list thereof) returned by \code{link{derepFastq}} can also be provided.
#'  These \code{\link{derep-class}} object(s) or fastq files should correspond to those used 
#'  as input to the the \code{\link{dada}} function when denoising the reverse reads.
#'  
#' @param minOverlap (Optional). Default 12.
#'  The minimum length of the overlap required for merging the forward and reverse reads. 
#'
#' @param maxMismatch (Optional). Default 0. 
#'  The maximum mismatches allowed in the overlap region.
#'  
#' @param returnRejects (Optional). Default FALSE.
#'  If TRUE, the pairs that that were rejected based on mismatches in the overlap
#'  region are retained in the return \code{data.frame}.
#'
#' @param propagateCol (Optional). \code{character}. Default \code{character(0)}.
#'  The return data.frame will include values from columns in the $clustering \code{data.frame}
#'  of the provided \code{\link{dada-class}} objects with the provided names.
#'
#' @param justConcatenate (Optional). Default FALSE.
#'  If TRUE, the forward and reverse-complemented reverse read are concatenated rather than merged,
#'    with a NNNNNNNNNN (10 Ns) spacer inserted between them.
#' 
#' @param trimOverhang (Optional). Default FALSE.
#'  If TRUE, "overhangs" in the alignment between the forwards and reverse read are trimmed off.
#'  "Overhangs" are when the reverse read extends past the start of the forward read, and vice-versa,
#'  as can happen when reads are longer than the amplicon and read into the other-direction primer region.
#' 
#' @param verbose (Optional). Default FALSE. 
#'  If TRUE, a summary of the function results are printed to standard output.
#'
#' @param ... (Optional). Further arguments to pass on to \code{\link{nwalign}}.
#'  By default, \code{mergePairs} uses alignment parameters that hevaily penalizes mismatches and gaps
#'  when aligning the forward and reverse sequences.
#' 
#' @return A \code{data.frame}, or a list of \code{data.frames}. 
#' 
#' The return \code{data.frame}(s) has a row for each unique pairing of forward/reverse denoised sequences, 
#' and the following columns:
#' \itemize{
#'  \item{\code{$abundance}: Number of reads corresponding to this forward/reverse combination.}
#'  \item{\code{$sequence}: The merged sequence.}
#'  \item{\code{$forward}: The index of the forward denoised sequence.}
#'  \item{\code{$reverse}: The index of the reverse denoised sequence.}
#'  \item{\code{$nmatch}: Number of matches nts in the overlap region.}
#'  \item{\code{$nmismatch}: Number of mismatches in the overlap region.}
#'  \item{\code{$nindel}: Number of indels in the overlap region.}
#'  \item{\code{$prefer}: The sequence used for the overlap region. 1=forward; 2=reverse.}
#'  \item{\code{$accept}: TRUE if overlap between forward and reverse denoised sequences was at least 
#'                \code{minOverlap} and had at most \code{maxMismatch} differences. FALSE otherwise.}
#'  \item{\code{$...}: Additional columns specified in \code{propagateCol}.}
#' }
#' A list of data.frames are returned if a list of input objects was provided.
#' 
#' @seealso \code{\link{derepFastq}}, \code{\link{dada}}, \code{\link{fastqPairedFilter}}
#' @export
#'
#' @importFrom methods is
#'  
#' @examples
#' fnF <- system.file("extdata", "sam1F.fastq.gz", package="dada2")
#' fnR = system.file("extdata", "sam1R.fastq.gz", package="dada2")
#' dadaF <- dada(fnF, selfConsist=TRUE)
#' dadaR <- dada(fnR, selfConsist=TRUE)
#' merger <- mergePairs(dadaF, fnF, dadaR, fnR)
#' merger <- mergePairs(dadaF, fnF, dadaR, fnR, returnRejects=TRUE, propagateCol=c("n0", "birth_ham"))
#' merger <- mergePairs(dadaF, fnF, dadaR, fnR, justConcatenate=TRUE)
#' 
mergePairs <- function(dadaF, derepF, dadaR, derepR, minOverlap = 12, maxMismatch=0, returnRejects=FALSE, propagateCol=character(0), justConcatenate=FALSE, trimOverhang=FALSE, verbose=FALSE, ...) {
  # Validate input
  if(is(dadaF, "dada")) dadaF <- list(dadaF)
  if(is(dadaR, "dada")) dadaR <- list(dadaR)
  if(is(derepF, "derep")) derepF <- list(derepF)
  else if(is(derepF, "character") && length(derepF)==1 && dir.exists(derepF)) derepF <- parseFastqDirectory(derepF)
  if(is(derepR, "derep")) derepR <- list(derepR)
  else if(is(derepR, "character") && length(derepR)==1 && dir.exists(derepR)) derepR <- parseFastqDirectory(derepR)
  if( !(is.list.of(dadaF, "dada") && is.list.of(dadaR, "dada")) ) {
    stop("dadaF and dadaR must be provided as dada-class objects or lists of dada-class objects.")
  }
  if( !( (is.list.of(derepF, "derep") || is(derepF, "character")) && 
         (is.list.of(derepR, "derep") || is(derepR, "character")) )) {
    stop("derepF and derepR must be provided as derep-class objects or as character vectors of filenames.")
  }
  # Perform merging
  nrecs <- c(length(dadaF), length(derepF), length(dadaR), length(derepR))
  if(length(unique(nrecs))>1) stop("The dadaF/derepF/dadaR/derepR arguments must be the same length.")
  
  rval <- lapply(seq_along(dadaF), function (i)  {
    mapF <- getDerep(derepF[[i]])$map
    mapR <- getDerep(derepR[[i]])$map
    if(!(is.integer(mapF) && is.integer(mapR))) stop("Incorrect format of $map in derep-class arguments.")
#    if(any(is.na(rF)) || any(is.na(rR))) stop("Non-corresponding maps and dada-outputs.")
    if(!(length(mapF) == length(mapR) && 
         max(mapF, na.rm=TRUE) == length(dadaF[[i]]$map) &&
         max(mapR, na.rm=TRUE) == length(dadaR[[i]]$map))) {
      stop("Non-corresponding derep-class and dada-class objects.")
    }
    rF <- dadaF[[i]]$map[mapF]
    rR <- dadaR[[i]]$map[mapR]
    
    pairdf <- data.frame(sequence = "", abundance=0, forward=rF, reverse=rR)
    ups <- unique(pairdf) # The unique forward/reverse pairs of denoised sequences
    keep <- !is.na(ups$forward) & !is.na(ups$reverse)
    ups <- ups[keep, ]
    if (nrow(ups)==0) {
        outnames <- c("sequence", "abundance", "forward", "reverse",
                      "nmatch", "nmismatch", "nindel", "prefer", "accept")
        ups <- data.frame(matrix(ncol = length(outnames), nrow = 0))
        names(ups) <- outnames
        if(verbose) {
            message("No paired-reads (in ZERO unique pairings) successfully merged out of ", nrow(pairdf), " pairings) input.")
        }
        return(ups)
    } else {
        Funqseq <- unname(as.character(dadaF[[i]]$clustering$sequence[ups$forward]))
        Runqseq <- rc(unname(as.character(dadaR[[i]]$clustering$sequence[ups$reverse])))
        if (justConcatenate == TRUE) {
          # Simply concatenate the sequences together
            ups$sequence <- mapply(function(x,y) paste0(x,"NNNNNNNNNN", y),
                                   Funqseq, Runqseq, SIMPLIFY=FALSE);  
            ups$nmatch <- 0
            ups$nmismatch <- 0
            ups$nindel <- 0
            ups$prefer <- NA
            ups$accept <- TRUE
        } else {
          # Align forward and reverse reads.
          # Use unbanded N-W align to compare forward/reverse
          # Adjusting align params to prioritize zero-mismatch merges
            tmp <- getDadaOpt(c("MATCH", "MISMATCH", "GAP_PENALTY"))
            if(maxMismatch==0) {
                setDadaOpt(MATCH=1L, MISMATCH=-64L, GAP_PENALTY=-64L)
            } else {
                setDadaOpt(MATCH=1L, MISMATCH=-8L, GAP_PENALTY=-8L)
            }
            alvecs <- mapply(function(x,y) nwalign(x,y,band=-1,...), Funqseq, Runqseq, SIMPLIFY=FALSE)
            setDadaOpt(tmp)
            outs <- t(sapply(alvecs, function(x) C_eval_pair(x[1], x[2])))
            ups$nmatch <- outs[,1]
            ups$nmismatch <- outs[,2]
            ups$nindel <- outs[,3]
            ups$prefer <- 1 + (dadaR[[i]]$clustering$n0[ups$reverse] > dadaF[[i]]$clustering$n0[ups$forward])
            ups$accept <- (ups$nmatch >= minOverlap) & ((ups$nmismatch + ups$nindel) <= maxMismatch)
          # Make the sequence
            ups$sequence <- mapply(C_pair_consensus, sapply(alvecs,`[`,1), sapply(alvecs,`[`,2), ups$prefer, trimOverhang);
          # Additional param to indicate whether 1:forward or 2:reverse takes precedence
          # Must also strip out any indels in the return
          # This function is only used here.
    }
    
        # Add abundance and sequence to the output data.frame
        tab <- table(pairdf$forward, pairdf$reverse)
        ups$abundance <- tab[cbind(ups$forward, ups$reverse)]
        ups$sequence[!ups$accept] <- ""
        # Add columns from forward/reverse clustering
        propagateCol <- propagateCol[propagateCol %in% colnames(dadaF[[i]]$clustering)]
        for(col in propagateCol) {
            ups[,paste0("F.",col)] <- dadaF[[i]]$clustering[ups$forward,col]
            ups[,paste0("R.",col)] <- dadaR[[i]]$clustering[ups$reverse,col]
        }
        # Sort output by abundance and name
        ups <- ups[order(ups$abundance, decreasing=TRUE),]
        rownames(ups) <- NULL
        if(verbose) {
            message(sum(ups$abundance[ups$accept]), " paired-reads (in ", sum(ups$accept), " unique pairings) successfully merged out of ", sum(ups$abundance), " (in ", nrow(ups), " pairings) input.")
        }
        if(!returnRejects) { ups <- ups[ups$accept,] }
    
        if(any(duplicated(ups$sequence))) {
            message("Duplicate sequences in merged output.")
        }
        return(ups)
    }
  })
  # Construct returns
  if(!is.null(names(dadaF))) names(rval) <- names(dadaF)
  if(length(rval) == 1) rval <- rval[[1]]
  return(rval)
}

#' @importFrom ShortRead FastqStreamer
#' @importFrom ShortRead id
#' @importFrom ShortRead yield
sameOrder <- function(fnF, fnR, qualityType = "Auto") {
  matched <- TRUE
  fF <- FastqStreamer(fnF)
  on.exit(close(fF))
  fR <- FastqStreamer(fnR)
  on.exit(close(fR), add=TRUE)
  
  while( length(suppressWarnings(fqF <- yield(fF, qualityType = qualityType)))
         && length(suppressWarnings(fqR <- yield(fR, qualityType = qualityType))) ) {
    idF <- trimTails(id(fqF), 1, " ")
    idR <- trimTails(id(fqR), 1, " ")
    matched <- matched && all(idF == idR)
  }
  return(matched)
}

isMatch <- function(al, minOverlap, verbose=FALSE) {
  out <- C_eval_pair(al[1], al[2]) # match, mismatch, indel
  if(verbose) { cat("Match/mismatch/indel:", out, "\n") }
  if(out[1] >= minOverlap && out[2] == 0 && out[3] == 0) {
    return(TRUE);
  } else {
    return(FALSE);
  }
}
