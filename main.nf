#!/usr/bin/env nextflow

if (params.help) {
	
	    log.info"""
	    =====================================================
	    APAeval QUANTIFICATION BENCHMARKING PIPELINE
		Author(s): Yuk Kei Wan (*1,*2), Asier Gonzalez (*3)
		*1 iRNA COSI
		*2 Genomic Institute of Singapore, A*STAR, Singapore
		*3 Barcelona Supercomputing Center, Barcelone, Spain
		2021
	    =====================================================
	    Usage:
	    Run the pipeline with default parameters:
	    nextflow run main.nf -profile docker
	    Run with user parameters:
 	    nextflow run main.nf -profile docker --input {driver.genes.file} --public_ref_dir {validation.reference.file} --participant_id {tool.name} --goldstandard_dir {gold.standards.dir} --challenges_ids {analyzed.challenges} --assess_dir {benchmark.data.dir} --results_dir {output.dir}
	    Mandatory arguments:
                --input		List of cancer genes prediction
				--community_id			Name or OEB permanent ID for the benchmarking community
                --public_ref_dir 		Directory with list of cancer genes used to validate the predictions
                --participant_id  		Name of the tool used for prediction
                --goldstandard_dir 		Dir that contains metrics reference datasets for all cancer types
                --challenges_ids  		List of challenge ids selected by the user, separated by spaces
                --assess_dir			Dir where the data for the benchmark are stored
	    Other options:
                --validation_result		The output directory where the results from validation step will be saved
				--assessment_results	The output directory where the results from the computed metrics step will be saved
				--outdir	The output directory where the consolidation of the benchmark will be saved
				--statsdir	The output directory with nextflow statistics
				--data_model_export_dir	The output dir where json file with benchmarking data model contents will be saved
	  			--otherdir					The output directory where custom results will be saved (no directory inside)
	    Flags:
                --help			Display this message
	    """.stripIndent()

	exit 1
} else {

	log.info """\

	     ==============================================
	     APAeval QUANTIFICATION BENCHMARKING PIPELINE
	     ==============================================
	         Input file: ${params.input}
	         Benchmarking community = ${params.community_id}
	         Public reference directory : ${params.public_ref_dir}
	         Tool name : ${params.participant_id}
	         Metrics reference datasets: ${params.goldstandard_dir}
	         Challenge ids: ${params.challenges_ids}
	         Published benchmark data: ${params.assess_dir}
	         Validation results directory: ${params.validation_result}
	         Assessment results directory: ${params.assessment_results}
	         Consolidated benchmark results directory: ${params.outdir}
	         Statistics results about nextflow run: ${params.statsdir}
	         Benchmarking data model file location: ${params.data_model_export_dir}
	         Directory with community-specific results: ${params.otherdir}

         """
	.stripIndent()

}


// input files

input_file = file(params.input)
ref_dir = Channel.fromPath( params.public_ref_dir, type: 'dir' )
tool_name = params.participant_id.replaceAll("\\s","_")
gold_standards_dir = Channel.fromPath(params.goldstandard_dir, type: 'dir' ) 
challenges_ids = params.challenges_ids
benchmark_data = Channel.fromPath(params.assess_dir, type: 'dir' )
community_id = params.community_id

// output 
validation_file = file(params.validation_result)
assessment_file = file(params.assessment_results)
aggregation_dir = file(params.outdir, type: 'dir')
// It is really a file in this implementation
data_model_export_dir = file(params.data_model_export_dir)
other_dir = file(params.otherdir, type: 'dir')


process validation {

	// validExitStatus 0,1
	tag "Validating input file format"
	
	publishDir "${validation_file.parent}", saveAs: { filename -> validation_file.name }, mode: 'copy'

	input:
	file input_file
	path ref_dir
	val challenges_ids
	val tool_name
	val community_id

	output:
	val task.exitStatus into EXIT_STAT
	file 'validation.json' into validation_out
	
	"""
	python /app/validation.py -i $input_file -r $ref_dir -com $community_id -c $challenges_ids -p $tool_name -o validation.json
	"""

}

process compute_metrics {

	tag "Computing benchmark metrics for submitted data"
	
	publishDir "${assessment_file.parent}", saveAs: { filename -> assessment_file.name }, mode: 'copy'

	input:
	val file_validated from EXIT_STAT
	file input_file
	val challenges_ids
	path gold_standards_dir
	val tool_name
	val community_id

	output:
	file 'assessment.json' into assessment_out

	when:
	file_validated == 0

	"""
	python3 /app/compute_metrics.py -i $input_file -c $challenges_ids -m $gold_standards_dir -p $tool_name -com $community_id -o assessment.json
	"""
}

process benchmark_consolidation {

	tag "Performing benchmark assessment and building plots"
	publishDir "${aggregation_dir.parent}", pattern: "aggregation_dir", saveAs: { filename -> aggregation_dir.name }, mode: 'copy'
	publishDir "${data_model_export_dir.parent}", pattern: "data_model_export.json", saveAs: { filename -> data_model_export_dir.name }, mode: 'copy'

	input:
	path benchmark_data
	file assessment_out
	file validation_out
	val challenges_ids
	
	output:
	path 'aggregation_dir', type: 'dir'
	path 'data_model_export.json'

	"""
	python /app/manage_assessment_data.py -b $benchmark_data -p $assessment_out -o aggregation_dir
	python /app/merge_data_model_files.py -p $validation_out -m $assessment_out -c $challenges_ids -a aggregation_dir -o data_model_export.json
	"""

}


workflow.onComplete { 
	println ( workflow.success ? "Done!" : "Oops .. something went wrong" )
}
