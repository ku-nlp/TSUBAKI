// java_sample.java

/*
  Compile:
  javac java_sample.java
*/

import java.net.URL;
import java.net.URLEncoder;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;


public class java_sample {
    public static void main (String[] args) throws Exception {
	if (args.length < 1) {
	    System.err.println("Usage: java java_sample query_string");
	    System.exit(1);
	}

	String PROTOCOL = "http";
	String SERVER = "tsubaki.ixnlp.nii.ac.jp";
	String API_ADDRESS = "api.cgi?&results=20&start=1&query=";
	String encodedQuery = URLEncoder.encode(args[0], "UTF8");

	URL api = new URL(PROTOCOL + "://" + SERVER + "/" + API_ADDRESS + encodedQuery);
	BufferedReader reader = new BufferedReader(new InputStreamReader((InputStream)api.getContent(), "UTF8"));

	String line;
	while ((line = reader.readLine()) != null) {
	    System.out.println(line);
	}
    }
}

