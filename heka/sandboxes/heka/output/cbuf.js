/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
function heka_parse_cbuf(data) {
    var start = 1;
    var cbuf = {};
    var lines = data.split("\n");
    cbuf.header = JSON.parse(lines[0]);
    cbuf.data = [];
    for (var i = start; i < lines.length; i++) {
        var line = lines[i];
        var inFields = line.split('\t');
        var fields = [];
        fields[0] = new Date((cbuf.header.time + (cbuf.header.seconds_per_row*(i-start)))*1000);
        for (var j = 0; j < inFields.length; j++) {
            fields[j+1] = parseFloat(inFields[j]);
        }
        cbuf.data.push(fields);
    }
    return cbuf;
}

function heka_load_cbuf(url, callback) {
    var req = new XMLHttpRequest();
    var caller = this;
    req.onreadystatechange = function () {
        if (req.readyState == 4) {
            if (req.status == 200 ||
                req.status == 0) {
                callback(heka_parse_cbuf(req.responseText));
            }
        }
    };
    req.open("GET", url, true);
    req.send(null);
}

function heka_load_cbuf_complete(cbuf) {
    var name = "graph";
    var plural = "";
    if ((cbuf.header.seconds_per_row * cbuf.header.rows) / 3600 > 1) {
        plural = "s";
    }
    document.getElementById('range').innerHTML =
    cbuf.header.seconds_per_row + " second aggregation for the last "
    + String((cbuf.header.seconds_per_row * cbuf.header.rows) / 3600) + " hour" + plural;
    var labels = ['Date'];
    for (var i = 0; i < cbuf.header.columns; i++) {
        labels.push(cbuf.header.column_info[i].name + " (" + cbuf.header.column_info[i].unit + ")");
    }
    var checkboxes = document.createElement('div');
    checkboxes.id = name + "_checkboxes";
    var div = document.createElement('div');
    div.id = name;
    div.setAttribute("style","width: 100%");
    document.body.appendChild(div);
    document.body.appendChild(document.createElement('br'));
    var ldv = cbuf.header.column_info.length * 200 + 150;
    if (ldv > 1024) ldv = 1024;
    var options = {labels: labels, labelsDivWidth: ldv, labelsDivStyles:{ 'textAlign': 'right'}};
    document.body.appendChild(checkboxes);
    graph = new Dygraph(div, cbuf.data, options);
    var colors = graph.getColors();
    for (var i = 1; i < graph.attr_("labels").length; i++) {
        var color = colors[i-1];
        checkboxes.innerHTML += '<input type="checkbox" id="' + (i-1).toString()
        + '" onClick="' + name
        + '.setVisibility(this.id, this.checked)" checked><label style="font-size: smaller; color: '
        + color + '">'+ graph.attr_("labels")[i] + '</label>&nbsp;';
    }
    checkboxes.innerHTML += '<br/><input type="checkbox" id="logscale" onClick="graph.updateOptions({ logscale: this.checked })">'
        + '<label style="font-size: smaller;">Log scale</label>';
    if (cbuf.annotations && cbuf.annotations.length > 0) {
        for (var i = 0; i < cbuf.annotations.length; i++) {
            cbuf.annotations[i].series = labels[cbuf.annotations[i].col];
        }
        graph.setAnnotations(cbuf.annotations);
    }
}

