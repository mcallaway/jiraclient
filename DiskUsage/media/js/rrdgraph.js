
function draw() {
  var group_name = unescape(location.search.substr(1)).toLowerCase();
  fname="rrd/" + group_name + ".rrd";

  document.write('<div id="rrdgraph"></div>');
  document.write('<div id="rrdgraph"><p>RRD Datafile: <a href="'+fname+'"</a>'+fname+'</p></div>');

  try {
    // From binaryXHR.js
    FetchBinaryURLAsync(fname,update_plot_handler);
  } catch (err) {
    alert("Failed loading "+fname+"\n"+err);
  }
}

// This is the callback function that,
// given a binary file object,
// verifies that it is a valid RRD archive
// and performs the update of the Web page
function update_plot_handler(bf) {
  var i_rrd_data=undefined;
  try {
    // From RRDFile.js
    var i_rrd_data=new RRDFile(bf);
  } catch(err) {
    alert("File "+fname+" is not a valid RRD archive!");
  }
  if (i_rrd_data!=undefined) {
    rrd_data=i_rrd_data;
    update_plot();
  }
}

// This function updates the Web Page with the data from the RRD
function update_plot() {

  var gtype_format={
    'total':{
      title:'total',label:'total',color:"#00ff00",lines: {show:true}
    },
    'used':{
      title:'used',label:'used',color:"#aa0000",checked:true
    },
  };

  var f=new rrdFlot("rrdgraph",rrd_data,null,gtype_format);
}
