-- Set these somewhere above this function

  local postmaster = 'tom+postmaster@kumomta.com'
  local host_name = 'pmta-host-fi1.vdk.fi'

-------- START Postmaster Alerts Function ------------------
function postmaster_alert (alertsubject,notice)
  -- Assumes that the variable 'postmaster' was set above ( or fails)
  -- Assumes that the variable 'host_name' was set above ( or fails)
  if postmaster ~= nil and host_name ~= nil then
    local newmid = "Message-Id:<" .. tostring(kumo.uuid.new_v1(simple)) .. ">\r\n"
    local newdate = tostring(os.date("%a, %d %b %Y %X +0000")) .. "\r\n"
    local newtenant = "X-Tenant:InternalAlerts\r\n"
    local newcontenttype = "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n"
    local alertsender = "alerts@" .. host_name
    local newtext = newmid .. newdate .. newtenant .. newcontenttype .. "FROM:" .. alertsender .. "\r\nTO:" .. postmaster .. "\r\nSUBJECT:" .. alertsubject .. "\r\n\r\n" .. notice .."\r\n.\r\n"

    kumo.api.inject.inject_v1 {
      envelope_sender = alertsender,
      content = "This is a test",
      recipients = { { email = postmaster } },
    }
  end
end
-------- END Postmaster Alerts Function ------------------



-- This is included as an example:
postmaster_alert ("new mail"," a new mail has been injected")
