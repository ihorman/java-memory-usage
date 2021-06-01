//@url('/getmemorystas')
//@req(envname)
import com.hivext.api.core.utils.Transport;

var appid = "cluster",
    appBaseUrl = "https://raw.githubusercontent.com/ihorman/java-memory-usage/master",
    debug = [],
    userSession,
    searchobj = {
        "domain": envname,
    }

    function ExecCmdById(cmd, params, nodeId) {
        return jelastic.env.control.ExecCmdById(envname, userSession, nodeId, toJSON([{
            "command": cmd,
            "params": params
        }]), true, "root");
    }

    function RunTest(nodeId) {

        var cmd = "wget",
            params = appBaseUrl + "/jmu.sh -O /tmp/jmu.sh";
        var resp = ExecCmdById(cmd, params, nodeId);
        debug.push(resp);
        var cmd = "bash",
            params = "/tmp/jmu.sh";
        var resp = ExecCmdById(cmd, params, nodeId);
        debug.push(resp);
        var cmd "rm",
            params = "-f /tmp/jmu.sh";
        ExecCmdById(cmd, params, nodeId);
    }
    var targetUid = jelastic.administration.cluster.SearchEnvs(appid, session, searchobj).array[0].uid;
    var resp = jelastic.system.admin.SigninAsUser(targetUid);
    if (resp.result != 0) return resp;
        userSession = resp.session;

    var nodes = jelastic.env.control.GetEnvInfo(envname, userSession).nodes;


for (var i = 0, n = nodes.length; i < n; i++) {
    if (nodes[i].nodeGroup == 'cp') {
        resp = RunTest(nodes[i].id);
        debug.push(resp);
    }
}
return debug;
