
using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.ProcessHelper;
using TeeJee.Misc;


public class DownloadTask : AsyncTask{

	// settings
	public bool status_in_kb = false;
	public int timeout_secs = 60;
	public int connect_timeout = App.connect_timeout_seconds;
	public int max_concurrent = App.concurrent_downloads;

	// download lists
	private Gee.ArrayList<DownloadItem> downloads;
	private Gee.HashMap<string, DownloadItem> map;

	private Gee.HashMap<string,Regex> regex = null;

	public DownloadTask(){

		base();
		
		downloads = new Gee.ArrayList<DownloadItem>();
		map = new Gee.HashMap<string, DownloadItem>();
		
		regex = new Gee.HashMap<string,Regex>();
		
		try {
			//Sample:
			//[#4df0c7 19283968B/45095814B(42%) CN:1 DL:105404B ETA:4m4s]
			regex["file-progress"] = new Regex("""^\[#([^ \t]+)[ \t]+([0-9]+)B\/([0-9]+)B\(([0-9]+)%\)[ \t]+[^ \t]+[ \t]+DL\:([0-9]+)B[ \t]+ETA\:([^ \]]+)\]""");

			//12/03 21:15:33 [NOTICE] Download complete: /home/teejee/.cache/ukuu/v4.7.8/CHANGES
			regex["file-complete"] = new Regex("""[0-9A-Z\/: ]*\[NOTICE\] Download complete\: (.*)""");

			//8ae3a3|OK  |    16KiB/s|/home/teejee/.cache/ukuu/v4.0.7-wily/index.html
			//bea740|OK  |        n/a|/home/teejee/.cache/ukuu/v4.0.9-wily/CHANGES
			regex["file-status"] = new Regex("""^([0-9A-Za-z]+)\|(OK|ERR)[ ]*\|[ ]*(n\/a|[0-9.]+[A-Za-z\/]+)\|(.*)""");
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	// execution ----------------------------

	public void add_to_queue(DownloadItem item){

		item.task = this;
		
		downloads.add(item);

		// set gid - 16 character hex string in lowercase
		
		do{
			item.gid = random_string(16,"0123456789abcdef").down();
		}
		while (map.has_key(item.gid_key));
		
		map[item.gid_key] = item;
	}

	public void clear_queue(){
		downloads.clear();
		map.clear();
	}

	public void execute() {

		prepare();

		begin();

		if (status == AppStatus.RUNNING){
		}
	}

	public void prepare() {
		string s = build_script();
		save_bash_script_temp(s, script_file);
	}

	private string build_script() {

		log_debug("build_script():");
		log_debug("working_dir="+working_dir);
		string list = "";
		string list_file = working_dir+"/download.list";
		foreach(var item in downloads){
			list += item.source_uri + "\n"
			+ "  gid=" + item.gid + "\n"
			+ "  dir=" + item.partial_dir + "\n"
			+ "  out=" + item.file_name + "\n";
		}
		file_write(list_file, list);

		string cmd = "aria2c"
		+ " --no-netrc true"
		+ " -i '%s'".printf(escape_single_quote(list_file))
		+ " --show-console-readout=false"
		+ " --summary-interval=1"
		+ " --auto-save-interval=1"
		+ " --human-readable=false"
		+ " --enable-color=false"
		+ " --allow-overwrite"
		+ " --connect-timeout=%d".printf(connect_timeout)
		+ " --timeout=%d".printf(timeout_secs)
		+ " --max-concurrent-downloads=%d".printf(max_concurrent)
		+ " --max-file-not-found=3"
		+ " --retry-wait=2";

		log_debug(cmd);

		return cmd;
	}

	public override void parse_stdout_line(string out_line){
		if (is_terminated) {
			return;
		}

		update_progress_parse_console_output(out_line);
	}

	public override void parse_stderr_line(string err_line){
		if (is_terminated) {
			return;
		}

		update_progress_parse_console_output(err_line);
	}

	public bool update_progress_parse_console_output (string line) {
		if ((line == null) || (line.length == 0)) {
			return true;
		}

		//log_debug(line);

		MatchInfo match;

		if (regex["file-complete"].match(line, 0, out match)) {
			//log_debug("match: file-complete: " + line);
			prg_count++;
		}
		else if (regex["file-status"].match(line, 0, out match)) {

			//8ae3a3|OK  |    16KiB/s|/home/teejee/.cache/ukuu/v4.0.7-wily/index.html

			//log_debug("match: file-status: " + line);

			// always display
			//log_debug(line);

			string gid_key = match.fetch(1).strip();
			string status = match.fetch(2).strip();
			int64 rate = int64.parse(match.fetch(3).strip());
			//string file = match.fetch(4).strip();

			if (map.has_key(gid_key)){
				map[gid_key].rate = rate;
				map[gid_key].status = status;
			}
		}
		else if (regex["file-progress"].match(line, 0, out match)) {

			//log_debug("match: file-progress: " + line);
			
			// Note: HTML files don't have content length, so bytes_total will be 0

			var gid_key = match.fetch(1).strip();
			var received = int64.parse(match.fetch(2).strip());
			var total = int64.parse(match.fetch(3).strip());
			//var percent = double.parse(match.fetch(4).strip());
			var rate = int64.parse(match.fetch(5).strip());
			var eta = match.fetch(6).strip();

			if (map.has_key(gid_key)){
				var item = map[gid_key];
				item.bytes_received = received;
				if (item.bytes_total == 0){
					item.bytes_total = total;
				}
				item.rate = rate;
				item.eta = eta;
				item.status = "RUNNING";

				status_line = item.status_line();
			}

			//log_debug(status_line);
		}
		else {
			//log_debug("unmatched: '%s'".printf(line));
		}

		return true;
	}

	protected override void finish_task(){
		mv_partials_to_finals();
		log_debug("DownloadTask():finish_task():dir_delete("+working_dir+"):");
		dir_delete(working_dir);
	}

	private void mv_partials_to_finals() {

		log_debug("mv_partials_to_finals()");

		foreach(var item in downloads){
			string d = file_parent(item.file_path_partial);

			if (!file_exists(item.file_path_partial)){
				log_debug("file_path_partial not found: %s".printf(item.file_path_partial));
				continue;
			}

			if (item.status == "OK"){
				file_move(item.file_path_partial, item.file_path);
			}
			else{
				file_delete(item.file_path_partial);
			}
			dir_delete(d);
		}
	}
}

public class DownloadItem : GLib.Object
{
	/* File is downloaded to 'partial_dir' and moved to 'download_dir'
	 * after successful completion. File will always be saved with
	 * the specified name 'file_name' instead of the source file name.
	 * */

	public string file_name = "";
	public string download_dir = "";
	public string partial_dir = "";
	public string source_uri = "";

	public string gid = ""; // ID
	public int64 bytes_total = 0;
	public int64 bytes_received = 0;
	public int64 rate = 0;
	public string eta = "";
	public string status = "";

	public DownloadTask task = null;

	public string file_path{
		owned get{
			return download_dir+"/"+file_name;
		}
	}

	public string file_path_partial{
		owned get{
			return partial_dir+"/"+file_name;
		}
	}

	public string gid_key{
		owned get{
			return gid.substring(0,6);;
		}
	}

	public DownloadItem(string _source_uri, string _download_dir, string _file_name){
		
		file_name = _file_name;
		download_dir = _download_dir;
		partial_dir = create_tmp_dir();
		source_uri = _source_uri;
	}

	public string status_line(){

		if (task.status_in_kb){
			return "%s / %s, %s/s (%s)".printf(
				format_file_size(bytes_received, false, "", true, 1),
				format_file_size(bytes_total, false, "", true, 1),
				format_file_size(rate, false, "", true, 1),
				eta).replace("\n","");
		}
		else{
			return "%s / %s, %s/s (%s)".printf(
				format_file_size(bytes_received),
				format_file_size(bytes_total),
				format_file_size(rate),
				eta).replace("\n","");
		}
	}
}
