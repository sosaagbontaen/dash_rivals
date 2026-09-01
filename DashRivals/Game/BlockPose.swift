// Generated from the Start Plank mocap: the four-point set position,
// sampled bone-by-bone. Frame 38 = on your marks, frame 52 = set.
// Regenerate by re-running the FK extraction over the .dae.
import SceneKit

enum BlockPose {
    static let marks: [(String, SCNQuaternion)] = [
        ("Hips", SCNQuaternion(0.644062, 0.089586, 0.033216, 0.758983)),
        ("Spine", SCNQuaternion(0.035458, 0.004867, 0.004768, 0.999348)),
        ("Spine1", SCNQuaternion(0.136943, 0.011850, -0.001148, 0.990507)),
        ("Spine2", SCNQuaternion(0.189177, 0.013425, -0.010106, 0.981799)),
        ("Neck", SCNQuaternion(-0.109424, -0.027064, 0.082121, 0.990227)),
        ("Head", SCNQuaternion(0.011692, -0.043791, -0.034857, 0.998364)),
        ("LeftShoulder", SCNQuaternion(0.478433, 0.473344, -0.466253, 0.574156)),
        ("LeftArm", SCNQuaternion(0.151124, -0.353757, 0.382698, 0.839976)),
        ("LeftForeArm", SCNQuaternion(0.000000, 0.021992, 0.524731, 0.850984)),
        ("LeftHand", SCNQuaternion(-0.514068, 0.025815, 0.067595, 0.854692)),
        ("RightShoulder", SCNQuaternion(0.459462, -0.488088, 0.427588, 0.606492)),
        ("RightArm", SCNQuaternion(-0.026016, 0.387847, -0.188299, 0.901910)),
        ("RightForeArm", SCNQuaternion(0.000000, -0.020686, -0.493546, 0.869474)),
        ("RightHand", SCNQuaternion(-0.625084, 0.013927, 0.203489, 0.753437)),
        ("LeftUpLeg", SCNQuaternion(0.103078, 0.966058, 0.228402, -0.062760)),
        ("LeftLeg", SCNQuaternion(-0.770583, -0.003472, -0.057469, 0.634733)),
        ("LeftFoot", SCNQuaternion(0.599773, -0.046175, -0.055623, 0.796898)),
        ("LeftToeBase", SCNQuaternion(0.365199, -0.012002, -0.046651, 0.929682)),
        ("RightUpLeg", SCNQuaternion(-0.041841, 0.428436, 0.902386, -0.019801)),
        ("RightLeg", SCNQuaternion(-0.480878, 0.063190, -0.067479, 0.871900)),
        ("RightFoot", SCNQuaternion(0.632991, 0.071169, -0.039244, 0.769881)),
        ("RightToeBase", SCNQuaternion(0.647349, 0.130145, 0.021098, 0.750704)),
    ]
    /// Hips local translation for this pose (model units).
    static let marksHips = SCNVector3(-8.6131, 122.0495, -28.0617)
    static let set: [(String, SCNQuaternion)] = [
        ("Hips", SCNQuaternion(0.695802, 0.065052, 0.011346, 0.715191)),
        ("Spine", SCNQuaternion(0.062520, -0.007987, 0.008776, 0.997973)),
        ("Spine1", SCNQuaternion(0.158299, -0.016931, -0.002786, 0.987242)),
        ("Spine2", SCNQuaternion(0.210740, -0.015326, -0.008939, 0.977381)),
        ("Neck", SCNQuaternion(-0.138012, -0.016199, 0.024158, 0.990003)),
        ("Head", SCNQuaternion(-0.018176, -0.011901, -0.013635, 0.999671)),
        ("LeftShoulder", SCNQuaternion(0.473358, 0.427492, -0.284590, 0.715676)),
        ("LeftArm", SCNQuaternion(-0.167627, -0.451920, -0.007128, 0.876139)),
        ("LeftForeArm", SCNQuaternion(0.000000, 0.024050, 0.573817, 0.818631)),
        ("LeftHand", SCNQuaternion(-0.637295, -0.139408, -0.127032, 0.747184)),
        ("RightShoulder", SCNQuaternion(0.413643, -0.532601, 0.442272, 0.591297)),
        ("RightArm", SCNQuaternion(-0.009239, 0.494476, -0.260522, 0.829179)),
        ("RightForeArm", SCNQuaternion(-0.000000, -0.026082, -0.622301, 0.782343)),
        ("RightHand", SCNQuaternion(-0.648173, -0.054402, 0.281486, 0.705463)),
        ("LeftUpLeg", SCNQuaternion(0.171877, 0.944813, 0.261646, -0.096581)),
        ("LeftLeg", SCNQuaternion(-0.809440, -0.000027, -0.060549, 0.584073)),
        ("LeftFoot", SCNQuaternion(0.619276, -0.049137, -0.068230, 0.780658)),
        ("LeftToeBase", SCNQuaternion(0.406968, -0.022015, -0.049381, 0.911841)),
        ("RightUpLeg", SCNQuaternion(-0.019711, 0.406342, 0.912908, -0.033105)),
        ("RightLeg", SCNQuaternion(-0.301429, 0.079825, -0.033031, 0.949567)),
        ("RightFoot", SCNQuaternion(0.555855, 0.029057, -0.071749, 0.827667)),
        ("RightToeBase", SCNQuaternion(0.652038, 0.117883, 0.014867, 0.748819)),
    ]
    /// Hips local translation for this pose (model units).
    static let setHips = SCNVector3(-12.8765, 127.7518, -17.1783)
}
