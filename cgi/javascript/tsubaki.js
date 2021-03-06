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
}

function submitQuery2 () {
    var removeSynids = new Array();
    var dpndStates = new Array();
    var termStates = new Array();
    for (var i = 0; i < queryGroups.length; i++) {
	for (var j = 0; j < queryGroups[i].termGroups.length; j++) {
            var states = queryGroups[i].termGroups[j].getState().split(",");
	    var dpnds  = queryGroups[i].termGroups[j].getDependency();

            termStates.push(queryGroups[i].getID() + "=" + queryGroups[i].termGroups[j].getID() + "=" + queryGroups[i].termGroups[j].getImportance());

	    for (var k = 0; k < dpnds.length; k++) {
		dpndStates.push(queryGroups[i].getID() + "=" + dpnds[k].child.getID() + "=" + dpnds[k].getImportance());
            }
            for (var k = 0; k < states.length; k++) {
		var kv = states[k].split("=");
		if (kv[1] == 0) {
                    removeSynids.push(kv[0]);
		}
            }
	}
    }
    document.getElementById("rm_synids").value  = removeSynids.join(",");
    document.getElementById("trm_states").value = termStates.join(",");
    document.getElementById("dep_states").value = dpndStates.join(",");
    document.search.submit();
}
