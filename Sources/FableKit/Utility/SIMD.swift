import Foundation
import simd

extension simd_float4x4 {
    var translation : SIMD3<Float> {
        return simd_float3(columns.3.x, columns.3.y, columns.3.z)
    }
    var upper3x3 : simd_float3x3 {
        return simd_float3x3(SIMD3<Float>(columns.0.w, columns.0.y, columns.0.z), SIMD3<Float>(columns.1.x, columns.1.w, columns.1.z), SIMD3<Float>(columns.2.x, columns.2.y, columns.2.w))
    }
}

extension simd_float4 {
    var float3 : simd_float3 {
        return simd_float3(x, y, z)
    }
}

extension simd_quatf {
    var angles: SIMD3<Float> {
        var angles = SIMD3<Float>();
        let qfloat = self.vector
        
        // heading = x, attitude = y, bank = z
        
        let test = qfloat.x*qfloat.y + qfloat.z*qfloat.w;
        
        if (test > 0.499) { // singularity at north pole
            
            angles.x = 2 * atan2(qfloat.x,qfloat.w)
            angles.y = (.pi / 2)
            angles.z = 0
            return  angles
        }
        if (test < -0.499) { // singularity at south pole
            angles.x = -2 * atan2(qfloat.x,qfloat.w)
            angles.y = -(.pi / 2)
            angles.z = 0
            return angles
        }
        
        
        let sqx = qfloat.x*qfloat.x;
        let sqy = qfloat.y*qfloat.y;
        let sqz = qfloat.z*qfloat.z;
        angles.x = atan2(2*qfloat.y*qfloat.w-2*qfloat.x*qfloat.z , 1 - 2*sqy - 2*sqz)
        angles.y = asin(2*test)
        angles.z = atan2(2*qfloat.x*qfloat.w-2*qfloat.y*qfloat.z , 1 - 2*sqx - 2*sqz)
        
        return angles
    }
}

extension SIMD3<Float> {
    var degrees: SIMD3<Float> {
        let degreePerRadian = (360 / Float.pi)
        return SIMD3(x: self.x * degreePerRadian, y: self.y * degreePerRadian, z: self.z * degreePerRadian)
    }
}
