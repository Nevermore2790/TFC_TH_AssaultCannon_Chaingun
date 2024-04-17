// They Hunger Chaingun which is actually from Team Fortress Classic.
// Might need some ideas on how to implement it. Right now, I might just stick to vanilla They Hunger stuff with my own twists.

#include "sven_scripted_utils"

namespace SVEN_TH_CHAINGUN
{



enum CHAINGUN_E
{
	CHAINGUN_IDLE = 0,
	CHAINGUN_IDLE2,
	CHAINGUN_SPINUP,
	CHAINGUN_SPINDOWN,
	CHAINGUN_FIRE,
	CHAINGUN_DRAW,
	CHAINGUN_HOLSTER
};

enum CHAINGUN_IN_ATTACK
{
	CHAINGUN_STOP = 0,
	CHAINGUN_IN_ATTACK,
	CHAINGUN_IN_ATTACK2,
};

// Models
string P_MODEL		= "models/hunger/p_tfac.mdl";
string V_MODEL		= "models/hunger/v_tfac.mdl";
string W_MODEL		= "models/hunger/w_tfac.mdl";

string SHELL_MDL 	= "models/shell_762.mdl";

// Sprites
string SPR_DIR		= "sven_weapons/";

// Sounds
array<string> TH_ChaingunSoundEvents = { 
		"weapons/hunger/asscan1.wav",
		"weapons/hunger/asscan2.wav",
		"weapons/hunger/asscan3.wav",
		"weapons/hunger/asscan4.wav",
		"weapons/reload1.wav",
		"weapons/reload2.wav",
		"weapons/reload3.wav",
		"weapons/357_cock1.wav"
};

// Weapon information
int MAX_CARRY    = SVEN_MAX_CARRY_556;
int MAX_CLIP     = 300;
int DEFAULT_GIVE = MAX_CLIP * 2;
int WEIGHT       = 20;
int FLAGS		= ITEM_FLAG_NOAUTORELOAD; // WeaponIdle() will take care of this.
uint SLOT		= 5;	// Moved to Slot 6 - Same slots for M249, Displacer, etc.
uint POSITION		= 9;
string AMMO_TYPE 	= SVEN_AMMO_556;

const CCVar@ g_SvenScriptedChaingun = CCVar("sven_th_chaingun_mp", 0, "", ConCommandFlag::AdminOnly); // as_command sven_th_chaingun_mp 0. 1 - MP Spread. 0 - SP Spread.

class weapon_th_chaingun_as : ScriptBasePlayerWeaponEntity, SvenScriptedWeaponUtils
{
	private CBasePlayer@ m_pPlayer
	{
		get const { return cast<CBasePlayer>(self.m_hPlayer.GetEntity()); }
		set       { self.m_hPlayer = EHandle(@value); }
	}
	
	private int CHAINGUN_BULLETS_PER_SHOT = 2;
	private float CHAINGUN_REDRAW_DURATION = (17.0 / 32.0);
	private int m_fInAttack;
	private int m_iSpecialReload;
	private int m_iShell;
	
	void Spawn()
	{
		Precache();
		g_EntityFuncs.SetModel( self, self.GetW_Model( W_MODEL ) );
		self.m_iDefaultAmmo = DEFAULT_GIVE;
		
		m_fInAttack = 0;
		m_iSpecialReload = 0;
		
		self.FallInit();
	}
	
	void Precache()
	{
		self.PrecacheCustomModels();
		g_Game.PrecacheModel( V_MODEL );
		g_Game.PrecacheModel( W_MODEL );
		g_Game.PrecacheModel( P_MODEL );

		m_iShell = g_Game.PrecacheModel( SHELL_MDL );

		for( uint i = 0; i < TH_ChaingunSoundEvents.length(); i++ )
		{
			g_SoundSystem.PrecacheSound( TH_ChaingunSoundEvents[i] );
			g_Game.PrecacheGeneric( "sound/" + TH_ChaingunSoundEvents[i] );
		}
	
		g_Game.PrecacheGeneric( "sprites/" + SPR_DIR + self.pev.classname + ".txt" );
	}
	
	bool GetItemInfo(ItemInfo& out info)
	{
		info.iMaxAmmo1 = MAX_CARRY;
		info.iMaxAmmo2 = -1;
		info.iAmmo1Drop = MAX_CLIP;
		info.iAmmo2Drop = -1;
		info.iMaxClip = MAX_CLIP;
		info.iFlags = FLAGS;
		info.iSlot = SLOT;
		info.iPosition = POSITION;
		info.iWeight = WEIGHT;
		info.iId = g_ItemRegistry.GetIdForName(pev.classname);

		return true;
	}
	
	bool AddToPlayer(CBasePlayer@ pPlayer)
	{
		if (!BaseClass.AddToPlayer(pPlayer))
			return false;

		NetworkMessage message(MSG_ONE, NetworkMessages::WeapPickup, pPlayer.edict());
			message.WriteLong(g_ItemRegistry.GetIdForName(pev.classname));
		message.End();

		return true;
	}

	bool PlayEmptySound()
	{
		if( self.m_bPlayEmptySound )
		{
			self.m_bPlayEmptySound = false;
			g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON, TH_ChaingunSoundEvents[7], 0.8, ATTN_NORM, 0, PITCH_NORM );
		}
		
		return false;
	}
	
	bool Deploy()
	{
		bool bResult = self.DefaultDeploy(self.GetV_Model( V_MODEL ), self.GetP_Model( P_MODEL ), CHAINGUN_DRAW, "egon" );	// Third person Player won't be having any reload animations. Expect them to see go doing Idle No-Weapon animation when it happens.
		self.m_flTimeWeaponIdle = WeaponTimeBase() + 1.0;
		return bResult;
	}
	
	void Holster(int skiplocal )
	{
		self.m_fInReload = false;

		m_pPlayer.m_flNextAttack = WeaponTimeBase() + 1.0f;
		self.m_flTimeWeaponIdle = WeaponTimeBase() + g_PlayerFuncs.SharedRandomFloat(m_pPlayer.random_seed, 10, 15);
		self.SendWeaponAnim( CHAINGUN_HOLSTER );

		// Stop chaingun sounds.
		StopSounds();

		// Restore player speed.
		SetPlayerSlow( false );

		m_fInAttack = 0;
		m_iSpecialReload = 0;
	}

	void PrimaryAttack()
	{
		// Don't fire while in reload.
		if ( m_iSpecialReload != 0 )
		{
			return;
		}

		// don't fire underwater, or if the clip is empty.
		if ( m_pPlayer.pev.waterlevel == WATERLEVEL_HEAD || self.m_iClip <= 0 )
		{
			if ( m_fInAttack != 0 )
			{
				// spin down
				SpinDown();
			}
			else if ( self.m_bFireOnEmpty )
			{
				self.PlayEmptySound();
				self.m_flNextSecondaryAttack = self.m_flNextPrimaryAttack = WeaponTimeBase() + 0.5f;
			}
			return;
		}

		if ( m_fInAttack == 0 )
		{
			// Spin up
			SpinUp();
		}
		else
		{
			// Spin
			Spin();
		}
	}

	void SecondaryAttack()
	{
		if ( m_fInAttack != 0)
		{
			SpinDown();
		}
	}

	void Reload()
	{
		if ( m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) <= 0 || self.m_iClip >= MAX_CLIP )
			return;

		// don't reload until recoil is done
		if ( self.m_flNextPrimaryAttack > WeaponTimeBase() )
			return;

		if ( m_fInAttack != 0 )
			return;
		
		// check to see if we're ready to reload
		if ( m_iSpecialReload == 0 )
		{
			self.SendWeaponAnim( CHAINGUN_HOLSTER );
			m_iSpecialReload = 1;
			m_pPlayer.m_flNextAttack = 0.5;
			self.m_flTimeWeaponIdle = g_Engine.time + 0.6;
			self.m_flNextPrimaryAttack = g_Engine.time + 0.6;
			self.m_flNextSecondaryAttack = g_Engine.time + 1.5;
			return;
		}
		else if ( m_iSpecialReload == 1 )
		{
			if ( self.m_flTimeWeaponIdle > g_Engine.time )
				return;
			// was waiting for gun to move to side
			m_iSpecialReload = 2;

			float flRand = g_PlayerFuncs.SharedRandomFloat(m_pPlayer.random_seed, 0, 1);
			if ( flRand >= 0.75 )
				g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_ITEM, TH_ChaingunSoundEvents[4], 1.0, ATTN_NORM, 0, 85 + Math.RandomLong( 0, 0x1f ) );
			else if ( flRand >= 0.5 )
				g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_ITEM, TH_ChaingunSoundEvents[5], 1.0, ATTN_NORM, 0, 85 + Math.RandomLong( 0, 0x1f ) );
			else
				g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_ITEM, TH_ChaingunSoundEvents[6], 1.0, ATTN_NORM, 0, 85 + Math.RandomLong( 0, 0x1f ) );

			self.m_flTimeWeaponIdle = g_Engine.time + 0.8;
		}
		else if ( m_iSpecialReload == 2 )
		{
			self.DefaultReload( MAX_CLIP, CHAINGUN_DRAW, CHAINGUN_REDRAW_DURATION );

			m_iSpecialReload = 0;

			// Used to immediatly complete the reload.
			//m_pPlayer.m_flNextAttack = g_Engine.time - 0.1;
			m_pPlayer.m_flNextAttack = 0.6;
			
			//self.m_flTimeWeaponIdle = g_Engine.time + CHAINGUN_REDRAW_DURATION;
			self.m_flTimeWeaponIdle = 1.25;
			
			// Delay next attack times to allow the draw sequence to complete.
			//self.m_flNextPrimaryAttack = self.m_flNextSecondaryAttack = g_Engine.time + CHAINGUN_REDRAW_DURATION;
			self.m_flNextPrimaryAttack = self.m_flNextSecondaryAttack = 1.25;
		}
		
		BaseClass.Reload();
	}

	void WeaponIdle()
	{
		if ( !self.m_bFireOnEmpty )
			self.ResetEmptySound();

		m_pPlayer.GetAutoaimVector(AUTOAIM_10DEGREES);

		if ( self.m_flTimeWeaponIdle > WeaponTimeBase() )
			return;

		if ( m_fInAttack != 0 )
		{
			//if (!((m_pPlayer->pev->button & IN_ATTACK) || (m_pPlayer->pev->button & IN_ATTACK2)))
			if ( !(m_pPlayer.pev.button & m_fInAttack == 1 || m_pPlayer.pev.button & m_fInAttack == 2 ) )
			{
				// Spin down
				SpinDown();
			}
		}
		else
		{
			if ( self.m_iClip == 0 && m_iSpecialReload == 0 && m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) != 0 )
			{
				self.Reload();
			}
			else if ( m_iSpecialReload != 0 )
			{
				if ( self.m_iClip <= MAX_CLIP && m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) != 0)
				{
					self.Reload();
				}
			}
			else
			{
				int iAnim;
				float flRand = g_PlayerFuncs.SharedRandomFloat(m_pPlayer.random_seed, 0, 1);
				if (flRand <= 0.5)
				{
					iAnim = CHAINGUN_IDLE;
					self.m_flTimeWeaponIdle = WeaponTimeBase() + (41.0 / 10.0);
				}
				else
				{
					iAnim = CHAINGUN_IDLE2;
					self.m_flTimeWeaponIdle = WeaponTimeBase() + (51.0 / 10.0);
				}
				self.SendWeaponAnim( iAnim );
			}
		}
	}

	bool ShouldWeaponIdle()
	{
		return true;
	}

	void SpinUp()
	{
		// spin up
		m_pPlayer.m_iWeaponVolume = QUIET_GUN_VOLUME;

		self.SendWeaponAnim( CHAINGUN_SPINUP );

		// Slowdown player.
		SetPlayerSlow( true );

		m_fInAttack = 1;
		self.m_flNextPrimaryAttack = self.m_flNextSecondaryAttack = WeaponTimeBase() + 0.5f;
		self.m_flTimeWeaponIdle = WeaponTimeBase() + 0.5f;
		
		g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON, TH_ChaingunSoundEvents[0], 1.0, ATTN_NORM, 0, 80 + Math.RandomLong( 0, 0x3f ) );
	}

	void SpinDown()
	{	
		// Spin down
		m_pPlayer.m_iWeaponVolume = QUIET_GUN_VOLUME;

		self.SendWeaponAnim( CHAINGUN_SPINDOWN );

		// Restore player speed.
		SetPlayerSlow( false );
		
		g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON, TH_ChaingunSoundEvents[2], 1.0, ATTN_NORM, 0, 80 + Math.RandomLong( 0, 0x3f ) );

		m_fInAttack = 0;
		self.m_flNextPrimaryAttack = self.m_flNextSecondaryAttack = WeaponTimeBase() + 1.0f;
		self.m_flTimeWeaponIdle = WeaponTimeBase() + 1.0f;
	}

	void Spin()
	{	
		m_fInAttack = 1;

		// Spin sound.
		g_SoundSystem.EmitSound( m_pPlayer.edict(), CHAN_ITEM, TH_ChaingunSoundEvents[3], 0.8, ATTN_NORM );
		
		if ( g_SvenScriptedChaingun.GetBool() )
			Fire(0.2, 0.1, false);
		else
			Fire(0.1, 0.1, false);
	}

	void Fire( float flSpread, float flCycleTime, bool bUseAutoAim )
	{
		m_pPlayer.m_iWeaponVolume = NORMAL_GUN_VOLUME;
		m_pPlayer.m_iWeaponFlash = NORMAL_GUN_FLASH;

		// The chaingun fires 2 bullets at a time, so we need to ensure it only shoot one bullet m_iClip is 1. 
		//int nShot = std::min( self.m_iClip, CHAINGUN_BULLETS_PER_SHOT );
		self.m_iClip -= CHAINGUN_BULLETS_PER_SHOT;

		m_pPlayer.pev.effects = ( int (m_pPlayer.pev.effects) ) | EF_MUZZLEFLASH;

		// player "shoot" animation
		m_pPlayer.SetAnimation( PLAYER_ATTACK1 );

		Math.MakeVectors(m_pPlayer.pev.v_angle + m_pPlayer.pev.punchangle);
		
		Vector vecSrc = m_pPlayer.GetGunPosition();
		Vector vecAiming = m_pPlayer.GetAutoaimVector(AUTOAIM_5DEGREES);
		Vector vecDir;
		
		FireBulletsPlayer( 2, vecSrc, vecAiming, Vector(flSpread, flSpread, flSpread), 8192.0f, BULLET_PLAYER_SAW, 0);

		pev.effects |= EF_MUZZLEFLASH;
		
		self.SendWeaponAnim( CHAINGUN_FIRE );
		m_pPlayer.pev.punchangle.x = -2.0;
		m_pPlayer.pev.punchangle.y = -1.0;

		Vector ShellVelocity, ShellOrigin;
		GetDefaultShellInfo(ShellVelocity, ShellOrigin, 14.0, -10.0, 8.0);
		g_EntityFuncs.EjectBrass(ShellOrigin, ShellVelocity, m_pPlayer.pev.angles[1], m_iShell, TE_BOUNCE_SHELL);
		
		g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON, TH_ChaingunSoundEvents[1], 1.0, ATTN_NORM, 0, 100 );
		
		if (self.m_iClip <= 0 && m_pPlayer.m_rgAmmo( self.m_iPrimaryAmmoType ) <= 0)
			m_pPlayer.SetSuitUpdate('!HEV_AMO0', false, 0);

		self.m_flNextPrimaryAttack = self.m_flNextSecondaryAttack = WeaponTimeBase() + flCycleTime;
		self.m_flTimeWeaponIdle = WeaponTimeBase() + flCycleTime;
	}

	void StopSounds()
	{
		g_SoundSystem.StopSound( m_pPlayer.edict(), CHAN_WEAPON, TH_ChaingunSoundEvents[0] );
		g_SoundSystem.StopSound( m_pPlayer.edict(), CHAN_WEAPON, TH_ChaingunSoundEvents[1] );
		g_SoundSystem.StopSound( m_pPlayer.edict(), CHAN_WEAPON, TH_ChaingunSoundEvents[2] );
		g_SoundSystem.StopSound( m_pPlayer.edict(), CHAN_ITEM, TH_ChaingunSoundEvents[3] );
	}

	void SetPlayerSlow( bool bSlowDown )
	{
		if ( !bSlowDown )
			m_pPlayer.SetMaxSpeedOverride( -1 );
		else
			m_pPlayer.SetMaxSpeedOverride( 150 );
	}

}

string GetAmmoName()
{
	return "ammo_556";
}

string GetName()
{
	return "weapon_th_chaingun_as";
}

void Register()
{
	if ( !g_CustomEntityFuncs.IsCustomEntity( GetName() ) )
	{
		g_CustomEntityFuncs.RegisterCustomEntity( "SVEN_TH_CHAINGUN::weapon_th_chaingun_as", GetName() );
		g_ItemRegistry.RegisterWeapon( GetName(), SPR_DIR, AMMO_TYPE, "", GetAmmoName() );
	}
}

} // End of namespace
