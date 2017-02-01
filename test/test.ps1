foreach ( $item in (import-csv ".\jobs\all-jobs.txt" -Delim "|") ) {
	$item
	}