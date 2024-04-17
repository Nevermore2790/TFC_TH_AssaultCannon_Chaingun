// Literally YOINKED from the Classic Weapons Pack script, and replaced some parameters to avoid potential conflicts especially when two of these scripts exist on the map.
// Same for weapons: 357, Desert Eagle and Shockroach. However, some of them have been modified with my own twists and use vanilla Sven Co-op models and stuff instead of relying on Classics.

array<int> g_SvenScriptedTracerCount(33);

//Default Ammo
//9mm
const string SVEN_AMMO_9MM			= "9mm";
const int SVEN_MAX_CARRY_9MM		= 250;
//buckshot
const string SVEN_AMMO_BUCK			= "buckshot";
const int SVEN_MAX_CARRY_BUCK		= 125;
//357
const string SVEN_AMMO_357			= "357";
const int SVEN_MAX_CARRY_357		= 36;
//m40a1
const string SVEN_AMMO_SNIPER		= "m40a1";
const int SVEN_MAX_CARRY_SNIPER 	= 15;
//556
const string SVEN_AMMO_556			= "556";
const int SVEN_MAX_CARRY_556		= 600;
//rockets
const string SVEN_AMMO_ROCKET		= "rockets";
const int SVEN_MAX_CARRY_ROCKET		= 5;
//uranium
const string SVEN_AMMO_URANIUM		= "uranium";
const int SVEN_MAX_CARRY_URANIUM	= 100;
//ARgrenades
const string SVEN_AMMO_M203			= "ARgrenades";
const int SVEN_MAX_CARRY_M203		= 10;
//sporeclip
const string SVEN_AMMO_SPORE		= "sporeclip";
const int SVEN_MAX_CARRY_SPORE		= 30;

const string SVEN_AMMO_HORNET		= "hornets";
const int SVEN_MAX_CARRY_HORNET		= 100; // Set to 8 for Vanilla values.

const string SVEN_AMMO_SHOCK		= "shock charges";
const int SVEN_MAX_CARRY_SHOCK		= 100; // Set to 10 for Vanilla values.

const int SVEN_MAX_CARRY_GRENADE	= 10;
const int SVEN_MAX_CARRY_SATCHEL	= 5;
const int SVEN_MAX_CARRY_TRIPMINE	= 5;
const int SVEN_MAX_CARRY_SNARK		= 15;
const int SVEN_MAX_CARRY_PENGUIN	= 9;

mixin class SvenScriptedWeaponUtils
{
	float WeaponTimeBase()
	{
		return g_Engine.time;
	}

	void GetDefaultShellInfo(Vector& out vecShellVelocity, Vector& out vecShellOrigin, float forwardScale, float upScale, float rightScale)
	{
		Vector forward, right, up;
		g_EngineFuncs.AngleVectors(m_pPlayer.pev.angles, forward, right, up);

		const float fR = Math.RandomFloat(50.0, 70.0);
		const float fU = Math.RandomFloat(100.0, 150.0);

		for (int i = 0; i < 3; i++)
		{
		vecShellVelocity[i] = m_pPlayer.pev.velocity[i] + right[i] * fR + up[i] * fU + forward[i] * 25.0;
		vecShellOrigin[i] = m_pPlayer.pev.origin[i] + m_pPlayer.pev.view_ofs[i] + up[i] * upScale + forward[i] * forwardScale + right[i] * rightScale;
		}
	}

	// Lost the addition of DMG_ALWAYSGIB to DMG_BULLET if iDamage > 16 and some cases for iBulletType
	void FireBulletsPlayer(uint cShots, Vector vecSrc, Vector vecDirShooting, Vector vecSpread, float flDistance, int iBulletType, int iTracerFreq)
	{
		TraceResult tr;
		float x, y;

		g_WeaponFuncs.ClearMultiDamage();

		for (uint iShot = 1; iShot <= cShots; iShot++)
		{
			// Use player's random seed.
			// get circular gaussian spread
			x = g_PlayerFuncs.SharedRandomFloat(m_pPlayer.random_seed + iShot, -0.5, 0.5) + g_PlayerFuncs.SharedRandomFloat(m_pPlayer.random_seed + (1 + iShot), -0.5, 0.5);
			y = g_PlayerFuncs.SharedRandomFloat(m_pPlayer.random_seed + (2 + iShot), -0.5, 0.5) + g_PlayerFuncs.SharedRandomFloat(m_pPlayer.random_seed + (3 + iShot), -0.5, 0.5);
			// There's a notable diference with g_Utility.GetCircularGaussianSpread(x, y)?

			Vector vecDir = vecDirShooting + x * vecSpread.x * g_Engine.v_right + y * vecSpread.y * g_Engine.v_up;
			Vector vecEnd = vecSrc + vecDir * flDistance;

			g_Utility.TraceLine(vecSrc, vecEnd, dont_ignore_monsters, m_pPlayer.edict(), tr);

			if (iTracerFreq != 0 && (g_SvenScriptedTracerCount[m_pPlayer.entindex()]++ % iTracerFreq) == 0)
			{
				// YOINKED from:
				// https://github.com/KernCore91/-SC-Insurgency-Weapons-Project/blob/master/scripts/maps/ins2/base.as#L691-L692
				Vector vecAttachOrigin, vecAttachAngles;
				g_EngineFuncs.GetAttachment(m_pPlayer.edict(), 0, vecAttachOrigin, vecAttachAngles);

				Vector vecTracerSrc = vecAttachOrigin + g_Engine.v_forward * 64.0;

				NetworkMessage message(MSG_PAS, NetworkMessages::SVC_TEMPENTITY, vecTracerSrc);
					message.WriteByte(TE_TRACER);
					message.WriteCoord(vecTracerSrc.x);
					message.WriteCoord(vecTracerSrc.y);
					message.WriteCoord(vecTracerSrc.z);
					message.WriteCoord(tr.vecEndPos.x);
					message.WriteCoord(tr.vecEndPos.y);
					message.WriteCoord(tr.vecEndPos.z);
				message.End();
			}

			// do damage, paint decals
			if (tr.flFraction < 1.0)
			{
				if (tr.pHit !is null)
				{
					CBaseEntity@ pHit = g_EntityFuncs.Instance(tr.pHit);

					if (pHit !is null)
					{
						switch (iBulletType)
						{
							case BULLET_PLAYER_357:
								pHit.TraceAttack(m_pPlayer.pev, g_EngineFuncs.CVarGetFloat('sk_plr_357_bullet'), vecEnd, tr, DMG_BULLET | DMG_NEVERGIB);
							break;

							case BULLET_PLAYER_EAGLE:
								// SC:66% of the magnum, OF:85% of the magnum; based on skillopfor.cfg
								pHit.TraceAttack(m_pPlayer.pev, g_EngineFuncs.CVarGetFloat('sk_plr_357_bullet') * 0.85, vecEnd, tr, DMG_BULLET | DMG_NEVERGIB);
							break;

							case BULLET_PLAYER_SAW:
								pHit.TraceAttack(m_pPlayer.pev, g_EngineFuncs.CVarGetFloat('sk_556_bullet'), vecEnd, tr, DMG_BULLET | DMG_NEVERGIB);
							break;

							case BULLET_PLAYER_SNIPER:
								pHit.TraceAttack(m_pPlayer.pev, g_EngineFuncs.CVarGetFloat('sk_plr_762_bullet'), vecEnd, tr, DMG_BULLET | DMG_NEVERGIB);
							break;
						}
					}

				g_SoundSystem.PlayHitSound(tr, vecSrc, vecEnd, iBulletType);

				if (pHit is null || pHit.IsBSPModel())
					g_WeaponFuncs.DecalGunshot(tr, iBulletType);
				}
			}
			// make bullet trails
			g_Utility.BubbleTrail(vecSrc, tr.vecEndPos, int((flDistance * tr.flFraction) / 64.0));
		}
		g_WeaponFuncs.ApplyMultiDamage(m_pPlayer.pev, m_pPlayer.pev);
	}
}
