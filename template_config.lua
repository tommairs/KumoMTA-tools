--[[ *************************************** ]]--
--    TEMPLATE.LUA
--    A version of config used to show complexity
--    and provide samples to copy from
--[[ *************************************** ]]--

local kumo = require 'kumo'

--[===========================================================================================]--
kumo.on('init', function()

    -- For debugging only
  kumo.set_diagnostic_log_filter 'kumod=debug'

-----------------------------------------------------
--[[ Define the Spool ]]--
-----------------------------------------------------
  kumo.define_spool {
    name = 'data',
    path = '/var/spool/kumomta/data',
    kind = 'RocksDB',
  }

  kumo.define_spool {
    name = 'meta',
    path = '/var/spool/kumomta/meta',
    kind = 'RocksDB',
  }
-----------------------------------------------------
--[[ Define logging parameters ]]--
-----------------------------------------------------

-- for local logs
  kumo.configure_local_logs {
    log_dir = '/var/log/kumomta',
    headers = { 'Subject', 'X-Customer-ID', 'X-Tenant' },
    per_record = {
      Reception = {
        suffix = '_recv',
        enable = true,
      },
      Delivery ={
        suffix = '_deliv',
        enable = true,
      },
      TransientFailure = {
        suffix = '_trans',
        enable = true,
      },
      Bounce = {
        suffix = '_perm',
        enable = true,
      },
      Any = {
        suffix = '_any',
        enable = true,
      },
    },
  }

-- for webhooks
   kumo.configure_log_hook {
     headers = { 'Subject', 'X-Customer-ID', 'X-Tenant' },
    per_record = {
      Reception = {
        suffix = '_recv',
        enable = true,
      },
      Delivery ={
        suffix = '_deliv',
        enable = true,
      },
      TransientFailure = {
        suffix = '_trans',
        enable = true,
      },
      Bounce = {
        suffix = '_perm',
        enable = true,
      },
      Any = {
        suffix = '_any',
        enable = true,
      },
    },
  }

-----------------------------------------------------
--[[ Configure Bounce Classifier ]]--
-----------------------------------------------------
  kumo.configure_bounce_classifier {
    files = {
      '/opt/kumomta/share/bounce_classifier/iana.toml',
    },
  }

-----------------------------------------------------
--[[ Configure listeners ]]--
-----------------------------------------------------

--for HTTP(s)
  kumo.start_http_listener {
    listen = '0.0.0.0:8000',
    -- allowed to access any http endpoint without additional auth
    trusted_hosts = { '127.0.0.1', '::1' },
  }

-- for SMTP
  for _, port in ipairs { 25, 2026, 587 } do
    kumo.start_esmtp_listener {
      listen = '0:' .. tostring(port),
      relay_hosts = { '127.0.0.1', '192.168.1.0/24' },
      tls_private_key = '/opt/kumomta/etc/tls/ca.key',
      tls_certificate = '/opt/kumomta/etc/tls/ca.crt',
      banner = "KumoMTA Dev2 Server",
      hostname = "kdev2.aasland.com",
    }
  end

-----------------------------------------------------
--[[ Define IP Egress Sources ]]--
-------------------------------------------------------
  kumo.define_egress_source {
    name = 'ip-1',
    source_address = '10.2.0.9',
    ehlo_domain = 'kdev2.aasland.com',
  }

-----------------------------------------------------
--[[ Define Egress Pools ]]--
-------------------------------------------------------
  kumo.define_egress_pool {
    name = 'Pool-1',
    entries = {
      { name = 'ip-1' },
    },
  }



----------------------------------------------------------------------------
end) -- END OF THE INIT EVENT
----------------------------------------------------------------------------

--[===========================================================================================]--

----------------------------------------------------------------------------
--[ Helpful Variables ]--
----------------------------------------------------------------------------
local TENANT_TO_POOL = {
  ['Alerts'] = 'Pool-1',
  ['Newsletters'] = 'Pool-1',
  ['Marketing'] = 'Pool-1',
  ['via_mg'] = 'Pool-1',
}

local TENANT_PARAMS = {
  Alerts = {
    max_age = '5 minutes',
  },
}

----------------------------------------------------------------------------
--[ Helper functions ]--
----------------------------------------------------------------------------
-- Helper function that merges the values from `src` into `dest`
function merge_into(src, dest)
  for k, v in pairs(src) do
    dest[k] = v
  end
end

----------------------------------------------------------------------------
--[[ Configure Webhook feed ]]--
----------------------------------------------------------------------------

  kumo.on('should_enqueue_log_record', function(msg)
  local log_record = msg:get_meta 'log_record'
  -- avoid an infinite loop caused by logging that we logged that we logged...
  -- Check the log record: if the record was destined for the webhook queue
  -- then it was a record of the webhook delivery attempt and we must not
  -- log its outcome via the webhook.
  if log_record.queue ~= 'webhook' then
    -- was some other event that we want to log via the webhook
    msg:set_meta('queue', 'webhook')
    return true
  end
  return false
  end)


-- This is a user-defined event that matches up to the custom_lua
-- constructor used in `get_queue_config` below.
-- It returns a lua connection object that can be used to "send"
-- messages to their destination.
kumo.on('make.webhook', function(domain, tenant, campaign)
  local connection = {}
  local client = kumo.http.build_client {}
  function connection:send(message)
    local response = client
      :post('http://webhooks.aasland.com:81/index.php')
      :header('Content-Type', 'application/json')
      :body(message:get_data())
      :send()

    local disposition = string.format(
      '%d %s: %s',
      response:status_code(),
      response:status_reason(),
      response:text()
    )

    if response:status_is_success() then
      return disposition
    end

    -- Signal that the webhook request failed.
    -- In this case the 500 status prevents us from retrying
    -- the webhook call again, but you could be more sophisticated
    -- and analyze the disposition to determine if retrying it
    -- would be useful and generate a 400 status instead.
    -- In that case, the message we be retryed later, until
    -- it reached it expiration.
    kumo.reject(500, disposition)
  end
  return connection
end)

------------------------------------------------
--[[ Configure an HTTP injector for Mailgun ]]--
------------------------------------------------
kumo.on('make.mailgun', function(domain, tenant, campaign)
  local client = kumo.http.build_client {}
  local sender = {}

  function sender:send(message)
    local request =
      client:post 'https://api.mailgun.net/v3/YOUR_DOMAIN/messages.mime'

    request:basic_auth('api', 'YOUR_API_KEY')
    request:form_multipart_data {
      to = message:recipient(),
      message = message:get_data(),
    }

    -- Make the request
    local response = request:send()

    -- and handle the result
    local disposition = string.format(
      '%d %s %s',
      response:status_code(),
      response:status_reason(),
      response:text()
    )
    if response:status_is_success() then
      -- Success!
      return disposition
    end

    -- Failed!
    kumo.reject(400, disposition)
  end
  return sender
end)


----------------------------------------------------------------------------
--[ Determine settings for egress paths]--
----------------------------------------------------------------------------
kumo.on('get_egress_path_config', function(domain, egress_source, site_name)
  return kumo.make_egress_path {
    connection_limit = 32,
    smtp_port = 587,
    enable_tls = "OpportunisticInsecure",
  }

end)
----------------------------------------------------------------------------
--[ Determine queue routing]--
----------------------------------------------------------------------------
kumo.on('get_queue_config', function(domain, tenant, campaign)
  local params = {
    egress_pool = TENANT_TO_POOL[tenant],
  }
  merge_into(TENANT_PARAMS[tenant] or {}, params)

  -- Routing for Webhooks delivery
    if domain == 'webhook' then
    return kumo.make_queue_config {
      protocol = {
        custom_lua = {
          constructor = 'make.webhook',
        },
      },
    }
  end

  -- Routing for Mailgun HTTP API
  if tenant == 'via_mg' then
    return kumo.make_queue_config {
      protocol = {
        custom_lua = {
          constructor = 'make.mailgun',
        },
      },
    }
  end
  -- Routing for SendGrid HTTP API
  if tenant == 'via_sg' then
    return kumo.make_queue_config {
      protocol = {
        custom_lua = {
          constructor = 'make.sendgrid',
        },
      },
    }
  end

  -- Routing for SparkPost HTTP API
  if tenant == 'via_sp' then
    return kumo.make_queue_config {
      protocol = {
        custom_lua = {
          constructor = 'make.sparkpost',
        },
      },
    }
  end



  return kumo.make_queue_config(params)
end)

----------------------------------------------------------------------------
--[ Determine what to do on SMTP message reception]--
----------------------------------------------------------------------------
kumo.on('smtp_server_message_received', function(msg)
  -- Assign tenant based on X-Tenant header.
  local err = msg:import_x_headers()
  local tenant = msg:get_meta 'x_tenant'

-- use this to route to a smarthost
--  msg:set_meta('queue', 'k.aasland.com')
end)

----------------------------------------------------------------------------
--[ Determine what to do on HTTP message reception]--
----------------------------------------------------------------------------
kumo.on('http_server_message_received', function(msg)
  -- Assign tenant based on X-Tenant header.
  local err = msg:import_x_headers()
  local tenant = msg:get_meta 'x_tenant'

-- use this to route to a smarthost
--  msg:set_meta('queue', 'smarthost_address')
end)


----------------------------------------------------------------------------
--[ EOF ]--
----------------------------------------------------------------------------
