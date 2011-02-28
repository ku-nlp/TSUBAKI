function send_questionnarie () {
    var q = document.search.qbox.value;
    var question = -1;
    for (var i = 0; i < document.questionnarieForm.question.length; i++) {
	if (document.questionnarieForm.question[i].checked) {
	    question = document.questionnarieForm.question[i].value;
	}
    }
    var msg = document.questionnarieForm.message.value;

    var param = "q=" + q + "&question=" + question + "&msg=" + msg;
    new Ajax.Request("http://tsubaki.ixnlp.nii.ac.jp/questionnarie.cgi", {method: 'get', parameters: param, onComplete: complete});
}

function complete (originalRequest) {
    var pane = document.getElementById('questionnaire');
    if (Prototype.Browser.IE) {
	alert("アンケート結果を送信しました。ご協力有難うございました。");
    } else {
	pane.innerHTML = "<TR><TD align='center'>アンケート結果を送信しました。<BR>ご協力有難うございました。</TD></TR>";
    }
}

function toggle_simpage_view (id, obj, open_label, close_label) {
    var disp = document.getElementById(id).style.display;
    if (disp == "block") {
        document.getElementById(id).style.display = "none";
        obj.innerHTML = open_label;
    } else {
        document.getElementById(id).style.display = "block";
        obj.innerHTML = close_label;
    }
}

function open_query_edit_window () {
    window.open();    
}

function hide_query_result () {
    var baroon = document.getElementById("baroon");
    baroon.style.display = "none";
}

function toggle_ipsj_verbose_view (id1, id2, id3, id4, obj, open_label, close_label) {
    var disp1 = document.getElementById(id1).style.display;
    if (disp1 == "block") {
        document.getElementById(id1).style.display = "none";
        document.getElementById(id3).style.display = "none";
        obj.innerHTML = close_label;
    } else {
        document.getElementById(id1).style.display = "block";
        document.getElementById(id3).style.display = "block";
        obj.innerHTML = open_label;
    }

    var disp2 = document.getElementById(id2).style.display;
    if (disp2 == "block") {
        document.getElementById(id2).style.display = "none";
        document.getElementById(id4).style.display = "none";
    } else {
        document.getElementById(id2).style.display = "block";
        document.getElementById(id4).style.display = "block";
    }
}

function submitQuery () {
    document.search.submit();
    parent.stmap.location = "http://www.cl.ecei.tohoku.ac.jp/stmap/api/evidence_search.cgi?q=" + encodeURI(document.all.query.value);
}

function submitQuery2 () {
    var removeSynids = new Array();
    var dpndStates = new Array();
    var termStates = new Array();
    for (var i = 0; i < termGroups.length; i++) {
        var states = termGroups[i].getState().split(",");
	var dpnds  = termGroups[i].getDependancy();

        termStates.push(termGroups[i].getID() + "=" + termGroups[i].getImportance());

	for (var j = 0; j < dpnds.length; j++) {
            dpndStates.push(dpnds[j].child.getID() + "=" + dpnds[j].getImportance());
        }
        for (var j = 0; j < states.length; j++) {
            var kv = states[j].split("=");
            if (kv[1] == 0) {
                removeSynids.push(kv[0]);
            }
        }
    }
    document.getElementById("rm_synids").value  = removeSynids.join(",");
    document.getElementById("trm_states").value = termStates.join(",");
    document.getElementById("dep_states").value = dpndStates.join(",");
    document.search.submit();
}
