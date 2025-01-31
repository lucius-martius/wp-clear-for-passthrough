lutils = require ("linking-utils")
cutils = require ("common-utils")
log = Log.open_topic ("s-linking-passthrough")

-- Check if the subject of the event is already linked to target
function already_linked_to_target(event)
   local si = event:get_subject()
   local si_flags = lutils:get_flags(si.id)
   local target = event:get_data("target")

   return target and si_flags.peer_id == target.id
end

-- Check whether the event subject needs passthrough
function subject_needs_passthrough(event)
   local si = event:get_subject()
   return si.properties["item.node.encoded-only"]:lower() == "true"
end

-- Clears the target from all existing links
function clear_target(event)
   local source = event:get_source()
   local si = event:get_subject()
   local target = event:get_data("target")

   local om = cutils.get_object_manager("session-item")

   for siLinkable in om:iterate {
      type = "SiLinkable",
      Constraint { "id" , "!", tostring(si.id), type = "gobject" },
   } do
      for siLink in om:iterate {
         type = "SiLink",
         Constraint { "out.item.id", "=", tostring(siLinkable.id) },
         Constraint { "in.item.id", "=", tostring(target.id) },
      } do
         local out_id = tonumber(siLink.properties["out.item.id"])
         local in_id = tonumber(siLink.properties["in.item.id"])
         local out_flags = lutils:get_flags(out_id)
         local in_flags = lutils:get_flags(in_id)
         in_flags.peer_id = nil
         out_flags.peer_id = nil
         out_flags.was_handled = nil
         siLink:remove()
         log.info("Removed link between " .. siLinkable.properties["node.name"] ..
                  " and " .. tostring(target.properties["node.name"]))
         -- We need to push a new event so a new target gets selected
         source:call("push-event", "select-target", siLinkable, 0)
      end
   end
end

-- Checks if the current target of the event has passthrough active
function passthrough_is_active(event)
   local target = event:get_data("target")
   local si = event:get_subject()
   local om = cutils.get_object_manager("session-item")

   for siLink in om:iterate {
      type = "SiLink",
      Constraint { "in.item.id", "=", tostring(target.id) },
   } do
      for siLinkable in om:iterate {
         type = "SiLinkable",
         Constraint { "id" , "=", siLink.properties["out.item.id"], type = "gobject" },
         Constraint { "id" , "!", si.id, type = "gobject" },
      } do
         if siLink.properties["passthrough"] == "1" then
            return true
         end
      end
   end

   return false
end

-- Switches the target of the event to the null_sink
function target_null_sink(event)
   local om = cutils.get_object_manager("session-item")
   local new_target = om:lookup {
      type = "SiLinkable",
      Constraint { "node.name", "=", "null_sink" }
   }

   if new_target then
      event:set_data("target", new_target)
   else
      log.error("Could not find node \"null_sink\"")
   end
end

-- A hook that clears the target for passthrough streams and asigns a null_sink target
-- when passthrough is in effect.
SimpleEventHook {
   name = "linking/clear_passthrough_target",
   after = "linking/find-default-target",
   before = "linking/prepare-link",
   interests = {
      EventInterest {
         Constraint { "event.type", "=", "select-target" },
      },
   },
   execute = function (event)
      local si = event:get_subject()
      if already_linked_to_target(event) then
         local target = event:get_data("target")
         log:debug("Node " .. si.properties["node.name"] ..
                  " is already linked to " .. target.properties["node.name"] .. ".")
         return
      elseif subject_needs_passthrough(event) then
         log:info("Node " .. si.properties["node.name"] ..
                  " wants passthrough. Clearing other links to target.")

         clear_target(event)
      elseif passthrough_is_active(event) then
         local target = event:get_data("target")
         log:info("Passthrough in effect on target " .. target.properties["node.name"] ..
                  ". Switching " .. si.properties["node.name"] .. " to null_sink.")

         target_null_sink(event)
      end
   end
}:register ()
