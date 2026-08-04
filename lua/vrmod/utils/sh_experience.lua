-- Pure Cube Experience gate helpers (shared / offline-testable).
-- No GMod I/O — decision only. Client UI lives in ui/cl_onboarding.lua.
g_VR = g_VR or {}
vrmod = vrmod or {}

--- When should auto Experience run?
-- force wins; disabled / complete never; native_wrapper + prior cal skips re-spam (G10).
function vrmod.Experience_ShouldRunFromState(st)
	st = st or {}
	if st.force then return true end
	if st.enabled == false then return false end
	if st.complete then return false end
	if st.native_wrapper and st.has_prior_cal then return false end
	return true
end
