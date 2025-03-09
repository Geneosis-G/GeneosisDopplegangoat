class DopplegangoatComponent extends GGMutatorComponent;

var GGGoat gMe;
var Dopplegangoat myMut;

struct FullMeshInfo
{
	var string mName;
	var SkeletalMesh mSkeletalMesh;
	var PhysicsAsset mPhysicsAsset;
	var AnimSet mAnimSet;
	var AnimTree mAnimTree;
	var array<MaterialInterface> mMaterials;
	var vector mTranslation;
	var vector2D mCollisionCylinder;
	var float mScale;
	var array<name> mAnimationNames;
	var name mBiteBoneName;
};
var array< FullMeshInfo > mFullMeshes;
var int mID;

var GGRB_Handle mGrabber;
var Actor mLastGrabbedItem;
var bool mCanLick;

var float mTotalTime;
var float mTransformTime;
var bool mIsTransforming;

var( AnimationAndSound ) NPCAnimationInfo mDefaultAnimationInfo;
var( AnimationAndSound ) NPCAnimationInfo mAttackAnimationInfo;
var( AnimationAndSound ) NPCAnimationInfo mRunAnimationInfo;
var( AnimationAndSound ) NPCAnimationInfo mCurrentAnimationInfo;

var bool mForceHorn;
var bool mForceKick;
var bool mForceAnimate;
var bool mAutoAnimate;
var bool mIsBackPressed;

/**
 * See super.
 */
function AttachToPlayer( GGGoat goat, optional GGMutator owningMutator )
{

	super.AttachToPlayer(goat, owningMutator);

	if(mGoat != none)
	{
		gMe=goat;
		myMut=Dopplegangoat(owningMutator);

		//SetRandomMesh();
	}
}

function SetRandomMesh()
{
	SetCustomMesh(-1);
}

function SetNextMesh()
{
	SetCustomMesh(mID+1>=mFullMeshes.Length?0:mID+1);
}

function SetPreviousMesh()
{
	SetCustomMesh(mID<=0?mFullMeshes.Length-2:mID-1);// -2 to skip Survivor (nudity)
}

function SetCustomMesh(int newMeshIndex)
{
	local int i;
	local vector grabLocation, headLocation, kickLocation;
	// skip Survivor (nudity)
	if(newMeshIndex == mFullMeshes.Length-1)
	{
		newMeshIndex=0;
	}
	// Override ID if set by command line
	if(myMut.mNextModel != -1)
	{
		newMeshIndex = myMut.mNextModel;
		myMut.mNextModel=-1;
	}
	// if ID out of bounds, get a random one
	if( newMeshIndex < 0 || newMeshIndex >= mFullMeshes.Length )
	{
		newMeshIndex=rand( mFullMeshes.Length );
	}
	// No lick during transformation
	gMe.DropGrabbedItem();
	if(mGrabber != none)
	{
		mGrabber.ReleaseComponent();
		mCanLick=true;
	}

	mID=newMeshIndex;
	myMut.WorldInfo.Game.Broadcast(myMut, mFullMeshes[ mID ].mName);
	// Set scale first to get a correct ragdoll scale
	if(mFullMeshes[ mID ].mScale != 0.f)
	{
		gMe.SetDrawScale(mFullMeshes[ mID ].mScale);
	}
	else
	{
		gMe.SetDrawScale(1.f);
	}
	// Set custom mesh and anims
	gMe.mesh.SetSkeletalMesh( mFullMeshes[ mID ].mSkeletalMesh );
	gMe.mesh.SetPhysicsAsset( mFullMeshes[ mID ].mPhysicsAsset, true);
	gMe.mesh.AnimSets[ 0 ] = mFullMeshes[ mID ].mAnimSet;
	gMe.mesh.SetAnimTreeTemplate( mFullMeshes[ mID ].mAnimTree );
	// Set custom material
	for(i=0 ; i<mFullMeshes[ mID ].mMaterials.Length ; i++)
	{
		gMe.mesh.SetMaterial( i, mFullMeshes[ mID ].mMaterials[i] );
	}

	// Set custom translation and collision
	gMe.mesh.SetTranslation(mFullMeshes[ mID ].mTranslation);
	gMe.SetLocation(gMe.Location + vect(0, 0, 1) * mFullMeshes[ mID ].mCollisionCylinder.Y);
	gMe.SetCollisionSize(mFullMeshes[ mID ].mCollisionCylinder.X, mFullMeshes[ mID ].mCollisionCylinder.Y);

	gMe.mCameraLookAtOffset=vect(0, 0, 1) * (mFullMeshes[ mID ].mCollisionCylinder.Y + 20.f);
	gMe.mDriverPosOffsetZ = GetDriverOffsetZ();

	// Use custom grabber if needed
	gMe.mesh.GetSocketWorldLocationAndRotation( 'grabSocket', grabLocation );
	if(SkelControlSingleBone( gMe.mesh.FindSkelControl( 'TongueController' ) ) != none
	&& gMe.mesh.GetAnimLength( gMe.mAbilities[EAT_Bite].mAnim ) != 0.f
	&& VSize(grabLocation) != 0.f)
	{
		gMe.mAbilities[EAT_Bite].mAnimNeckBlendListIndex=1;
		gMe.mAbilities[EAT_Bite].mRange=mFullMeshes[ mID ].mCollisionCylinder.X + 75.f + GetExtraRange();
		if(gMe.mGrabber == none)
		{
			gMe.mGrabber=mGrabber;
			mGrabber=none;
		}
	}
	else
	{
		gMe.mAbilities[EAT_Bite].mAnimNeckBlendListIndex=INDEX_NONE;
		gMe.mAbilities[EAT_Bite].mRange=mFullMeshes[ mID ].mCollisionCylinder.X + 75.f + GetExtraRange();
		if(mGrabber == none)
		{
			mGrabber=gMe.mGrabber;
			gMe.mGrabber=none;
		}
	}

	// Use custom attack if needed
	gMe.mesh.GetSocketWorldLocationAndRotation( gMe.mHeadbuttDamageSourceSocket, headLocation );
	if(gMe.mesh.GetAnimLength( gMe.mAbilities[EAT_Horn].mAnim ) != 0.f
	&& VSize(headLocation) != 0.f
	&& !NeedForceAttack())
	{
		mForceHorn=false;
	}
	else
	{
		mForceHorn=true;
	}
	gMe.mesh.GetSocketWorldLocationAndRotation( 'kickSocket', kickLocation );
	if(gMe.mesh.GetAnimLength( gMe.mAbilities[EAT_Kick].mAnim ) != 0.f
	&& VSize(headLocation) != 0.f
	&& !NeedForceAttack())
	{
		mForceKick=false;
	}
	else
	{
		mForceKick=true;
	}

	// Update ability ranges
	mGoat.mAbilities[ EAT_Horn ].mRange = FMax(100.f - mFullMeshes[ mID ].mCollisionCylinder.X, mFullMeshes[ mID ].mCollisionCylinder.X + 20.f) + GetExtraRange();
	mGoat.mAbilities[ EAT_Kick ].mRange = FMax(110.f - mFullMeshes[ mID ].mCollisionCylinder.X, mFullMeshes[ mID ].mCollisionCylinder.X + 30.f) + GetExtraRange();
	// Set default anims
	mDefaultAnimationInfo.AnimationNames[0]='Idle';
	if(!IsAnimInSet('Idle'))
	{
		mDefaultAnimationInfo.AnimationNames[0]='Idle_01';
		if(!IsAnimInSet('Idle_01'))
		{
			mDefaultAnimationInfo.AnimationNames[0]='Idle_02';
		}
	}
	mRunAnimationInfo.AnimationNames[0]='Sprint';
	if(!IsAnimInSet('Sprint'))
	{
		mRunAnimationInfo.AnimationNames[0]='Sprint_01';
		if(!IsAnimInSet('Sprint_01'))
		{
			mRunAnimationInfo.AnimationNames[0]='Sprint_02';
			if(!IsAnimInSet('Sprint_02'))
			{
				mRunAnimationInfo.AnimationNames[0]='Run';
				if(!IsAnimInSet('Run'))
				{
					mRunAnimationInfo.AnimationNames[0]='Walk';
				}
			}
		}
	}
	mAttackAnimationInfo.AnimationNames[0]='Ram';
	if(!IsAnimInSet('Ram'))
	{
		mAttackAnimationInfo.AnimationNames[0]='Attack';
		if(!IsAnimInSet('Attack'))
		{
			mAttackAnimationInfo.AnimationNames[0]='Kick';
		}
	}
	// Set custom anims
	if(mFullMeshes[ mID ].mAnimationNames.Length > 0 && mFullMeshes[ mID ].mAnimationNames[0] != '')
	{
		mDefaultAnimationInfo.AnimationNames[0]=mFullMeshes[ mID ].mAnimationNames[0];
	}
	if(mFullMeshes[ mID ].mAnimationNames.Length > 1 && mFullMeshes[ mID ].mAnimationNames[1] != '')
	{
		mRunAnimationInfo.AnimationNames[0]=mFullMeshes[ mID ].mAnimationNames[1];
	}
	if(mFullMeshes[ mID ].mAnimationNames.Length > 2 && mFullMeshes[ mID ].mAnimationNames[2] != '')
	{
		mAttackAnimationInfo.AnimationNames[0]=mFullMeshes[ mID ].mAnimationNames[2];
	}

	// Force custom anim if needed
	if((!(IsAnimInSet('Run') || IsAnimInSet('Run_01') || IsAnimInSet('Run_02') || IsAnimInSet('Run_03'))
	 || !(IsAnimInSet('Sprint') || IsAnimInSet('Sprint_01') || IsAnimInSet('Sprint_02') || IsAnimInSet('Sprint_03')))
	&& !IgnoreAutoAnimate())
	{
		mForceAnimate=true;
		mAutoAnimate=true;
	}
	else
	{
		mForceAnimate=false;
		mAutoAnimate=false;
	}

	//Update body weights
	gMe.OnPlayerModified();
	//Update camera zoom
	ModifyCameraZoom(gMe);
	// Fix anim tree ?
	PostInitAnimTree(gMe.mesh);
	//myMut.WorldInfo.Game.Broadcast(myMut, "mGrabber=" $ mGrabber $ "mForceHorn=" $ mForceHorn $ "mForceKick=" $ mForceKick $ "mForceAnimate=" $ mForceAnimate);
}

function float GetDriverOffsetZ()
{
	if(mFullMeshes[ mID ].mPhysicsAsset == PhysicsAsset'goat.mesh.goat_Physics'
	|| mFullMeshes[ mID ].mPhysicsAsset == PhysicsAsset'Heist_CatCircle.mesh.Cat_Physics_01'
	|| mFullMeshes[ mID ].mPhysicsAsset == PhysicsAsset'Space_HalfAGoat.Meshes.HalfGoat_PhysicsAsset'
	|| mFullMeshes[ mID ].mPhysicsAsset == PhysicsAsset'ClassyGoat.mesh.ClassyGoat_Physics_01'
	|| mFullMeshes[ mID ].mPhysicsAsset == PhysicsAsset'MMO_Dodo.mesh.DodoAbomination_Physics_01'
	|| mFullMeshes[ mID ].mPhysicsAsset == PhysicsAsset'MMO_Demon.mesh.Demon_Physics_01'
	|| mFullMeshes[ mID ].mPhysicsAsset == PhysicsAsset'MMO_Shredder.mesh.Shredder_Physics_01'
	|| mFullMeshes[ mID ].mPhysicsAsset == PhysicsAsset'MMO_Genie.mesh.Genie_Physics_01')
	{
		return -50.f;
	}
	else if(mFullMeshes[ mID ].mPhysicsAsset == PhysicsAsset'TallGoat.mesh.TallGoat_Physics_01')
	{
		return 40.f;
	}

	return 0.f;
}

function ModifyCameraZoom( GGGoat goat )
{
	local GGCameraModeOrbital orbitalCamera;

	orbitalCamera = GGCameraModeOrbital( GGCamera( PlayerController( goat.Controller ).PlayerCamera ).mCameraModes[ CM_ORBIT ] );

	orbitalCamera.mMaxZoomDistance = FMax(goat.GetCollisionRadius() * 6.f, 800);
	orbitalCamera.mMinZoomDistance = goat.GetCollisionRadius();
	orbitalCamera.mDesiredZoomDistance = 800;
	orbitalCamera.mCurrentZoomDistance = 800;
}

function bool IsAnimInSet(name animName)
{
	local AnimSequence animSeq;

	foreach gMe.mesh.AnimSets[0].Sequences(animSeq)
	{
		if(animSeq.SequenceName == animName)
		{
			return true;
		}
	}

	return false;
}
// Heist characters and bread animate fine on their own
function bool IgnoreAutoAnimate()
{
	return mFullMeshes[ mID ].mAnimTree == AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree'
	    || mFullMeshes[ mID ].mAnimTree == AnimTree'I_Am_Bread.Anim.Slice_AnimTree';
}

// Give extra range to some models
function float GetExtraRange()
{
	if(mFullMeshes[ mID ].mName == "Horse"
	|| mFullMeshes[ mID ].mName == "Lavahorse"
	|| mFullMeshes[ mID ].mName == "Demon")
	{
		return 35.f;
	}

	return 0.f;
}

function bool NeedForceAttack()
{
	return mFullMeshes[ mID ].mName == "Sheep"
		|| mFullMeshes[ mID ].mName == "Spacesheep"
		|| mFullMeshes[ mID ].mName == "Snail";
}

function PostInitAnimTree( SkeletalMeshComponent skelComp )
{
	local SkelControlLookAt tmpControl;

	if( skelComp.FindSkelControl( 'HeadControl' ) != none )
	{
		tmpControl = SkelControlLookAt( skelComp.FindSkelControl( 'HeadControl' ) );
		tmpControl.TargetLocationSpace = BCS_WorldSpace;
		tmpControl.SetSkelControlActive( false );
		tmpControl.TargetLocationInterpSpeed = 5.0f;
	}

	if( skelComp.FindSkelControl( 'ArmLControl' ) != none )
	{
		tmpControl = SkelControlLookAt( skelComp.FindSkelControl( 'ArmLControl' ) );
		tmpControl.TargetLocationSpace = BCS_WorldSpace;
		tmpControl.SetSkelControlActive( false );
	}

	if( skelComp.FindSkelControl( 'ArmRControl' ) != none )
	{
		tmpControl = SkelControlLookAt( skelComp.FindSkelControl( 'ArmRControl' ) );
		tmpControl.TargetLocationSpace = BCS_WorldSpace;
		tmpControl.SetSkelControlActive( false );
	}

	gMe.PostInitAnimTree(skelComp);
}

function Transform()
{
	local float frontAngle, rightAngle, leftAngle;
	local vector frontVector, leftVector, rightVector, camVector, camLocation;
	local rotator camRotation;

	//Depending on the camera angle, do previous, next or random transformation
	if(gMe.Controller != none && gMe.DrivenVehicle == none)
	{
		GGPlayerControllerGame( gMe.Controller ).PlayerCamera.GetCameraViewPoint( camLocation, camRotation );
	}

	camVector = Normal2D(vector(camRotation));
	frontVector = Normal2D(vector(gMe.Rotation));
	leftVector = Normal(frontVector cross vect(0, 0, 1));
	rightVector = -rightVector;

	// Cancel if camera looking vertically, or driving vehicle, or not possessed or goat looking vertically
	if(VSize(camVector) == 0.f || VSize(frontVector) == 0.f)
		return;

	frontAngle = Acos((camVector.x*frontVector.x) + (camVector.y*frontVector.y) + (camVector.z*frontVector.z));
	rightAngle = Acos((camVector.x*rightVector.x) + (camVector.y*rightVector.y) + (camVector.z*rightVector.z));
	leftAngle = Acos((camVector.x*leftVector.x) + (camVector.y*leftVector.y) + (camVector.z*leftVector.z));

	if(frontAngle <= rightAngle && frontAngle <= leftAngle)
	{
		SetRandomMesh();
	}
	else if(rightAngle <= leftAngle)
	{
		SetNextMesh();
	}
	else
	{
		SetPreviousMesh();
	}
}

function KeyState( name newKey, EKeyState keyState, PlayerController PCOwner )
{
	local GGPlayerInputGame localInput;

	if(PCOwner != gMe.Controller)
		return;

	localInput = GGPlayerInputGame( PCOwner.PlayerInput );

	if( keyState == KS_Down )
	{
		if( newKey == 'Y' || newKey == 'XboxTypeS_LeftThumbStick' || newKey == 'U')
		{
			mIsTransforming=true;
		}

		if( localInput.IsKeyIsPressed( "GBA_AbilityBite", string( newKey ) ) )
		{
			ForceLick();
		}

		if(localInput.IsKeyIsPressed("LeftMouseButton", string( newKey )) || newKey == 'XboxTypeS_RightTrigger')
		{
			if(mIsBackPressed)
			{
				ForceKick();
			}
			else
			{
				ForceHorn();
			}
		}

		if( localInput.IsKeyIsPressed( "GBA_Back", string( newKey ) ) )
		{
			mIsBackPressed=true;
		}

		if( localInput.IsKeyIsPressed( "GBA_ToggleRagdoll", string( newKey ) ) )
		{
			ForceUnragdoll();
		}
	}
	else if( keyState == KS_Up )
	{
		if( newKey == 'Y' || newKey == 'XboxTypeS_LeftThumbStick' || newKey == 'U')
		{
			mIsTransforming=false;
		}

		if( localInput.IsKeyIsPressed( "GBA_Back", string( newKey ) ) )
		{
			mIsBackPressed=false;
		}
	}
}

function Tick(float deltaTime)
{
	if(mIsTransforming)
	{
		//No transformation if moving or ragdoll
		if(gMe.mIsRagdoll || VSize2D(gMe.Velocity) > 0.1f)
		{
			mIsTransforming=false;
		}
	}
	// Change form
	if(mIsTransforming)
	{
		mTotalTime = mTotalTime + deltaTime;
		if(mTotalTime >= mTransformTime)
		{
			Transform();
			mTotalTime = 0.f;
		}
	}
	else
	{
		mTotalTime = 0.f;
	}

	//Fix state
	if(gMe.IsInState('AbilityBite') && gMe.Mesh.GetAnimLength( gMe.mAbilities[ EAT_Bite ].mAnim ) == 0.f)
	{
		gMe.GotoState( '' );
	}
	else if(gMe.IsInState('AbilityHorn') && gMe.Mesh.GetAnimLength( gMe.mAbilities[ EAT_Horn ].mAnim ) == 0.f)
	{
		gMe.GotoState( '' );
	}
	else if(gMe.IsInState('AbilityKick') && gMe.Mesh.GetAnimLength( gMe.mAbilities[ EAT_Kick ].mAnim ) == 0.f)
	{
		gMe.GotoState( '' );
	}
	else if(gMe.mBaaing && gMe.Mesh.GetAnimLength('Baa') == 0.f)
	{
		gMe.StopBaa();
	}

	// Lick stuff
	if( mGrabber != none )
	{
		UpdateGrabber( deltaTime );
		if(mLastGrabbedItem != none && gMe.mGrabbedItem == none)
		{
			mGrabber.ReleaseComponent();
			mCanLick=false;//Prevent instant lick after dropping an item
			gMe.SetTimer(0.1f, false, NameOf(AllowLick), self);
		}
	}

	// Animate stuff
	if(mForceAnimate && mAutoAnimate)
	{
		ResetAnim();
	}

	mLastGrabbedItem=gMe.mGrabbedItem;
}

function AllowLick()
{
	mCanLick=true;
}

function ResetAnim()
{
	local bool useFallingAnim;

	useFallingAnim=IsAnimInSet('Falling');
	if(useFallingAnim)
	{
		if(gMe.mIsInAir)
		{
			if(gMe.mAnimNodeSlot.GetPlayedAnimation() != 'Falling')
			{
				gMe.mAnimNodeSlot.PlayCustomAnim( 'Falling', 1.0f, 0.2f, 0.2f, true, true);
			}
		}
		else
		{
			if(gMe.mAnimNodeSlot.GetPlayedAnimation() == 'Falling')
			{
				gMe.mAnimNodeSlot.StopCustomAnim( 0.2f );
			}
		}
	}
	if(!gMe.mIsInAir || !useFallingAnim)
	{
		if(Vsize2D(gMe.Velocity) == 0.f)
		{
			if(gMe.mAnimNodeSlot.GetPlayedAnimation() != mDefaultAnimationInfo.AnimationNames[0])
			{
				gMe.mAnimNodeSlot.PlayCustomAnim( mDefaultAnimationInfo.AnimationNames[0], mDefaultAnimationInfo.AnimationRate, 0, 0, mDefaultAnimationInfo.LoopAnimation );
			}
		}
		else
		{
			if(gMe.mAnimNodeSlot.GetPlayedAnimation() != mRunAnimationInfo.AnimationNames[0])
			{
				gMe.mAnimNodeSlot.PlayCustomAnim( mRunAnimationInfo.AnimationNames[0], mRunAnimationInfo.AnimationRate, 0, 0, mRunAnimationInfo.LoopAnimation );
			}
		}
	}
}

//////////////////////////////////
// Force lick stuff
//////////////////////////////////


function ForceLick()
{
	local GGAbility ability;
	local vector biteLocation;
	local Actor grabVictim;
	local GGCollidableActorInterface collidable;
	local bool grabbedSuccessfully;

	//myMut.WorldInfo.Game.Broadcast(myMut, "ForceLick mGrabber=" $ mGrabber $ ", gMe.Physics=" $ gMe.Physics $ ", gMe.mTerminatingRagdoll=" $ gMe.mTerminatingRagdoll $
	//", gMe.mBaaing=" $ gMe.mBaaing $ ", mCanLick=" $ mCanLick $ ", gMe.mGrabbedItem=" $ gMe.mGrabbedItem);
	if( mGrabber == none || gMe.Physics == PHYS_RigidBody || gMe.mTerminatingRagdoll || gMe.mBaaing || !mCanLick)
		return;

	if( gMe.mGrabbedItem != none )
	{
		gMe.DropGrabbedItem();
		return;
	}

	gMe.mGrabbedLocalLocation = vect( 0.0f, 0.0f, 0.0f );
	ability = gMe.mAbilities[ EAT_Bite ];
	gMe.PlaySound( SoundCue'Goat_Sounds.Cue.Effect_Goat_lick_cue', true, false, true );

	biteLocation=GetGrabLocation();
	grabVictim = FindGrabbableItem( biteLocation, ability.mRange );

	if( grabVictim != none )
	{
		grabbedSuccessfully = GrabItem( grabVictim, biteLocation );
		if( grabbedSuccessfully )
		{
			GrabbedItem( ability, grabVictim );
		}

		collidable = GGCollidableActorInterface( grabVictim );
		if( collidable != none )
		{
			collidable.SetCollisionChainGoatNr( gMe );
		}
	}
}

function GrabbedItem( GGAbility ability, Actor grabVictim )
{
	GGHUD( PlayerCOntroller( gMe.Controller ).myHUD ).mHUDMovie.ActorGrabbed( grabVictim );

	GGGameInfo( gMe.WorldInfo.Game ).OnUseAbility( gMe, ability, grabVictim );

	if( GGScoreActorInterface( grabVictim ) != none )
	{
		if( string( GGScoreActorInterface( grabVictim ).GetPhysMat() ) == "PhysMat_HangGlider" )
		{
			GGPlayerControllerGame( gMe.Controller ).mAchievementHandler.UnlockAchievement( ACH_MILE_HIGH_CLUB );
		}
		else if( string( GGScoreActorInterface( grabVictim ).GetPhysMat() ) == "PhysMat_Axe" )
		{
			GGPlayerControllerGame( gMe.Controller ).mAchievementHandler.UnlockAchievement( ACH_JOHNNY );
		}
	}

	gMe.TriggerGlobalEventClass( class'GGSeqEvent_GrabbedObject', gMe.Controller );
}

function Actor FindGrabbableItem( vector grabLocation, float grabRange )
{
	local Actor foundActor, hitActor;
	local TraceHitInfo hitInfo;
	local name boneName;
	local GGGrabbableActorInterface grabbableInterface;

	foundActor = none;

	foreach gMe.VisibleCollidingActors( class'Actor', hitActor, grabRange, grabLocation,,,,, hitInfo )
	{
		grabbableInterface = GGGrabbableActorInterface( hitActor );

		if( grabbableInterface == none || hitActor == gMe )
		{
			continue;
		}

		if( foundActor != none && VSizeSq( hitActor.Location - grabLocation ) > VSizeSq( foundActor.Location - grabLocation ) )
		{
			continue;
		}

		boneName = grabbableInterface.GetGrabInfo( grabLocation );

		if( grabbableInterface.CanBeGrabbed( gMe, boneName ) )
		{
			foundActor = hitActor;
		}
	}

	return foundActor;
}

function bool GrabItem( Actor item, vector grabLocation )
{
	local name boneName;
	local PrimitiveComponent grabComponent;
	local vector dummyExtent, dummyOutPoint, closestPoint;
	local GJKResult closestPointResult;
	local GGPhysicalMaterialProperty physProp;
	local GGGrabbableActorInterface grabbableInterface;

	grabbableInterface = GGGrabbableActorInterface( item );

	if( grabbableInterface == none )
	{
		return false;
	}

	boneName = grabbableInterface.GetGrabInfo( grabLocation );

	if( grabbableInterface.CanBeGrabbed( gMe, boneName ) )
	{
		grabComponent = grabbableInterface.GetGrabbableComponent();
		physProp = grabbableInterface.GetPhysProp();

		grabbableInterface.OnGrabbed( gMe );
	}
	else
	{
		return false;
	}

	// Grab the item.
	mGrabber.GrabComponent( grabComponent, boneName, grabLocation, false );
	gMe.mActorsToIgnoreBlockingBy.AddItem( item );
	gMe.mGrabbedItem = item;

	// Cache location for the tongue. Have to check for grabbed component if the goat has grabbed a consumeable
	if( mGrabber.GrabbedBoneName == 'None' && mGrabber.GrabbedComponent != none )
	{
		closestPointResult = mGrabber.GrabbedComponent.ClosestPointOnComponentToPoint( grabLocation, dummyExtent, dummyOutPoint, closestPoint );
		if( closestPointResult == GJK_NoIntersection )
		{
			gMe.mGrabbedLocalLocation = InverseTransformVector( mGrabber.GrabbedComponent.LocalToWorld, closestPoint );
		}
		else
		{
			gMe.mGrabbedLocalLocation = InverseTransformVector( mGrabber.GrabbedComponent.LocalToWorld, gMe.mGrabbedItem.Location );
		}
	}

	if( physProp != none && physProp.ShouldAlertNPCs() )
	{
		gMe.NotifyAIControlllersGrabbedItem();
	}

	return true;
}

function UpdateGrabber( float deltaTime )
{
	local vector grabLocation;

	if( gMe.mGrabbedItem == none
		|| mGrabber.GrabbedComponent == none
		|| gMe.mGrabbedItem.bPendingDelete
		|| gMe.mGrabbedItem.Physics == PHYS_None )
	{
		gMe.DropGrabbedItem();
	}
	else
	{
		// Uqly hax to initialize the tongue the first time.
		if( gMe.mTongueControl.StrengthTarget == 0.0f )
		{
			gMe.SetTongueActive( true );
		}

		grabLocation=GetGrabLocation();
		mGrabber.SetLocation( grabLocation );

		// If we should reduce the mass of the KActor we picked up
		if( GGKActor( gMe.mGrabbedItem ) != None && gMe.mScaleMassOnPickup )
		{
			GGKActor( gMe.mGrabbedItem ).SetMassScale( gMe.mScaleMassRate );
		}

		if( mGrabber.GrabbedBoneName != 'None' )
		{
			gMe.mTongueControl.BoneTranslation = SkeletalMeshComponent( mGrabber.GrabbedComponent ).GetBoneLocation( mGrabber.GrabbedBoneName );
		}
		else
		{
			gMe.mTongueControl.BoneTranslation = TransformVector( mGrabber.GrabbedComponent.LocalToWorld, gMe.mGrabbedLocalLocation );
		}

		if( GGInterpActor( gMe.mGrabbedItem ) != none )
		{
			gMe.UpdateGrabbedInterpActor( deltaTime );
		}
	}
}

function vector GetGrabLocation()
{
	local vector loc;

	loc=gMe.mesh.GetBoneLocation(mFullMeshes[ mID ].mBiteBoneName);
	//myMut.WorldInfo.Game.Broadcast(myMut, "biteLocation=" $ biteLocation);
	//myMut.WorldInfo.Game.Broadcast(myMut, "Location=" $ gMe.Location);
	//myMut.WorldInfo.Game.Broadcast(myMut, "dist=" $ VSize(gMe.Location - biteLocation));
	if(VSize(loc) == 0.f)
	{
		loc=gMe.Location + (Normal(vector(gMe.Rotation)) * gMe.GetCollisionRadius());
	}

	return loc;
}

function ForceHorn()
{
	local float animLength, animTime;
	//myMut.WorldInfo.Game.Broadcast(myMut, "ForceHorn gMe.Physics=" $ gMe.Physics $ "gMe.mTerminatingRagdoll=" $ gMe.mTerminatingRagdoll $ "gMe.mBaaing=" $ gMe.mBaaing $
	//"mForceHorn=" $ mForceHorn $ "AnimationNames[0]=" $ mAttackAnimationInfo.AnimationNames[0] $ "SoundToPlay[0]=" $ mAttackAnimationInfo.SoundToPlay[0]);
	if( gMe.Physics == PHYS_RigidBody || gMe.mTerminatingRagdoll || gMe.mBaaing || !mForceHorn)
		return;

	gMe.ClearTimer(NameOf(EndAnim), self);
	gMe.ClearTimer(NameOf(HornAttack), self);

	gMe.DropGrabbedItem();
	// Play anim
	mAutoAnimate=false;
	if(!NeedForceAttack())//Sheep knows how to attack, he is just not doing any damages
	{
		animLength =  gMe.mAnimNodeSlot.PlayCustomAnim( mAttackAnimationInfo.AnimationNames[0], mAttackAnimationInfo.AnimationRate, 0, 0, mAttackAnimationInfo.LoopAnimation );
	}
	if(animLength != 0)
	{
		animTime = FMin(animLength, 2.f);
		gMe.SetTimer(animTime, false, NameOf(EndAnim), self);
		gMe.SetTimer(animTime/2.f, false, NameOf(HornAttack), self);
	}
	else
	{
		EndAnim();
		HornAttack();
	}
}

function HornAttack()
{
	local GGAbility ability;
	local vector direction, headLocation;
	local array< Actor > attackVictims;
	local int i;

	if( gMe.Physics == PHYS_RigidBody || gMe.mTerminatingRagdoll || gMe.mBaaing || !mForceHorn)
		return;

	// Play sound
	if(mAttackAnimationInfo.SoundToPlay.Length > 0 && mAttackAnimationInfo.SoundToPlay[0] != none)
	{
		gMe.PlaySound( mAttackAnimationInfo.SoundToPlay[0], true, false, true );
	}
	else
	{
		gMe.PlaySound( SoundCue'Goat_Sounds.Cue.HeadButt_Cue', true, false, true );
	}
	// do attack
	ability = gMe.mAbilities[ EAT_Horn ];
	headLocation = GetGrabLocation();

	direction = vector( gMe.Rotation );

	attackVictims = gMe.DealDirectionalDamage( ability.mDamage, ability.mRange, ability.mDamageTypeClass, ability.mDamageTypeClass.default.mDamageImpulse * gMe.mAttackMomentumMultiplier, headLocation, direction, gMe.Controller );
	for( i = 0; i < attackVictims.Length; i++ )
	{
		GGGameInfo( gMe.WorldInfo.Game ).OnUseAbility( gMe, ability, attackVictims[ i ] );
	}
}

function ForceKick()
{
	local float animLength, animTime;
	//myMut.WorldInfo.Game.Broadcast(myMut, "ForceKick gMe.Physics=" $ gMe.Physics $ "gMe.mTerminatingRagdoll=" $ gMe.mTerminatingRagdoll $ "gMe.mBaaing=" $ gMe.mBaaing $
	//"mForceKick=" $ mForceKick $ "AnimationNames[0]=" $ mAttackAnimationInfo.AnimationNames[0] $ "SoundToPlay[0]=" $ mAttackAnimationInfo.SoundToPlay[0]);
	if(gMe.mIsSprinting || gMe.Physics == PHYS_RigidBody || gMe.Physics == PHYS_Flying || gMe.mTerminatingRagdoll || gMe.mBaaing || !mForceKick)
		return;

	gMe.ClearTimer(NameOf(EndAnim), self);
	gMe.ClearTimer(NameOf(KickAttack), self);

	// Play anim
	mAutoAnimate=false;
	if(!NeedForceAttack())//Sheep knows how to attack, he is just not doing any damages
	{
		animLength =  gMe.mAnimNodeSlot.PlayCustomAnim( mAttackAnimationInfo.AnimationNames[0], mAttackAnimationInfo.AnimationRate, 0, 0, mAttackAnimationInfo.LoopAnimation );
	}
	if(animLength != 0)
	{
		animTime = FMin(animLength, 2.f);
		gMe.SetTimer(animTime, false, NameOf(EndAnim), self);
		gMe.SetTimer(animTime/2.f, false, NameOf(KickAttack), self);
	}
	else
	{
		EndAnim();
		KickAttack();
	}
}

function KickAttack()
{
	local GGAbility ability;
	local vector direction, kickLocation;
	local array< Actor > attackVictims;
	local int i;

	if(gMe.mIsSprinting || gMe.Physics == PHYS_RigidBody || gMe.Physics == PHYS_Flying || gMe.mTerminatingRagdoll || gMe.mBaaing || !mForceKick)
		return;

	// Play sound
	if(mAttackAnimationInfo.SoundToPlay.Length > 0 && mAttackAnimationInfo.SoundToPlay[0] != none)
	{
		gMe.PlaySound( mAttackAnimationInfo.SoundToPlay[0], true, false, true );
	}
	else
	{
		gMe.PlaySound( SoundCue'Goat_Sounds.Cue.HeadButt_Cue', true, false, true );
	}

	ability = gMe.mAbilities[ EAT_Kick ];
	kickLocation = gMe.Location - (Normal(vector(gMe.Rotation)) * gMe.GetCollisionRadius());

	direction = -vector( gMe.Rotation );

	attackVictims = gMe.DealDirectionalDamage( ability.mDamage, ability.mRange, ability.mDamageTypeClass, ability.mDamageTypeClass.default.mDamageImpulse * gMe.mAttackMomentumMultiplier, kickLocation, direction, gMe.Controller );
	for( i = 0; i < attackVictims.Length; i++ )
	{
		if( attackVictims[ i ] == gMe.mGrabbedItem )
		{
			gMe.DropGrabbedItem();
		}

		GGGameInfo( gMe.WorldInfo.Game ).OnUseAbility( gMe, ability, attackVictims[ i ] );
	}
}

function EndAnim()
{
	mAutoAnimate=true;
}
//Some models have troubles to stand up, help them
function ForceUnragdoll()
{
	if(mFullMeshes[ mID ].mName != "Dwarf"
	&& mFullMeshes[ mID ].mName != "Shredder")
		return;

	if(!gMe.mIsRagdoll)
		return;

	if(VSizeSq( gMe.Velocity ) < gMe.mStandUpThresholdVel * gMe.mStandUpThresholdVel
	&& gMe.mIsInAir)
	{
		gMe.mIsInAir=false;
		gMe.StandUp();
	}
}

defaultproperties
{
	mCanLick=true

	mID=0
	mTransformTime=1.f

	mDefaultAnimationInfo=(AnimationNames=(Idle),AnimationRate=1.0f,MovementSpeed=0.0f,LoopAnimation=true)
	mAttackAnimationInfo=(AnimationNames=(Ram),AnimationRate=1.0f,MovementSpeed=0.0f,LoopAnimation=false)
	mRunAnimationInfo=(AnimationNames=(Sprint),AnimationRate=1.0f,MovementSpeed=700.0f,LoopAnimation=true)
	//Goats
	mFullMeshes.Add((mName="Goat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'goat.Materials.Goat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Browngoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'goat.Materials.Goat_Mat_04'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Whitegoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'goat.Materials.Goat_Mat_05'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Blackgoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'goat.Materials.Goat_Mat_07'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Devilgoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'goat.Materials.Goat_Mat_02'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Bloodgoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'goat.Materials.Goat_Mat_06'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Angelgoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'goat.Materials.Goat_Mat_03'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Redgoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'CaptureTheFlag.Materials.Goat_RED_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Bluegoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'CaptureTheFlag.Materials.Goat_BLUE_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Unclegoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'goat.Materials.Goat_Mat_08'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Voodoogoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.Goat_Voodoo_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Prototypegoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.Goat_Prototype_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Zombiegoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.Goat_Zero_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Zombiegoat2",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.Goat_Zero_Mat_02'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Pixelgoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.Goat_EarlyAccess_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Cubegoat",mSkeletalMesh=SkeletalMesh'GoatCraft.mesh.BuilderGoat_01',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'GoatCraft.Materials.BuilderGoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Halfgoat",mSkeletalMesh=SkeletalMesh'Space_HalfAGoat.Meshes.HalfGoat_Rig_01',mPhysicsAsset=PhysicsAsset'Space_HalfAGoat.Meshes.HalfGoat_PhysicsAsset',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Space_HalfAGoat.Materials.HalfAGoat_Mat_01',Material'Space_Effects.Materials.HalfAGoat_Vortex_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f))
	mFullMeshes.Add((mName="Rippedgoat",mSkeletalMesh=SkeletalMesh'goat.mesh.GoatRipped',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'goat.Materials.Goat_Ripped_Mat_01'),mTranslation=(Z=20.f),mCollisionCylinder=(X=25.f,Y=30.f),mScale=1.2f))
	mFullMeshes.Add((mName="Heisengoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.Heisengoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f))
	mFullMeshes.Add((mName="Goatgoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.GoatGoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f))
	mFullMeshes.Add((mName="Mergoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.Mergoat_Body_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Spidergoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.SpiderGoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Aliengoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(MaterialInstanceConstant'Space_DarkQueen_Goat.Materials.QueenBody2_INST'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f))
	mFullMeshes.Add((mName="Piggygoat",mSkeletalMesh=SkeletalMesh'Space_CrowdfundingGoat.Meshes.CrowdfundingGoat_01',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Space_CrowdfundingGoat.Materials.CrowdfundingGoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f))
	mFullMeshes.Add((mName="Spacegoat",mSkeletalMesh=SkeletalMesh'goat.mesh.goat',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Space_GoatSpaceSuit.Materials.Goat_SpaceSuit_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f))
	//Farm animals
	mFullMeshes.Add((mName="Cow",mSkeletalMesh=SkeletalMesh'Space_MilkyWayGoat.Meshes.MilkyWayGoat_01',mPhysicsAsset=PhysicsAsset'Space_MilkyWayGoat.Meshes.MilkyWayGoat_Physics_01',mAnimSet=AnimSet'Space_MilkyWayGoat.Anim.MilkyWayGoat_Anim_01',mAnimTree=AnimTree'Space_MilkyWayGoat.MilkyWayGoat_AnimTree',mMaterials=(Material'MMO_Cow.Materials.Cow_Mat_01'),mCollisionCylinder=(X=40.f,Y=80.f)))
	mFullMeshes.Add((mName="Spacecow",mSkeletalMesh=SkeletalMesh'Space_MilkyWayGoat.Meshes.MilkyWayGoat_01',mPhysicsAsset=PhysicsAsset'Space_MilkyWayGoat.Meshes.MilkyWayGoat_Physics_01',mAnimSet=AnimSet'Space_MilkyWayGoat.Anim.MilkyWayGoat_Anim_01',mAnimTree=AnimTree'Space_MilkyWayGoat.MilkyWayGoat_AnimTree',mMaterials=(MaterialInstanceConstant'Space_MilkyWayGoat.Materials.CompanionCow_Mat_INST'),mCollisionCylinder=(X=40.f,Y=80.f)))
	mFullMeshes.Add((mName="Horse",mSkeletalMesh=SkeletalMesh'MMO_JoustingGoat.mesh.Horse_01',mPhysicsAsset=PhysicsAsset'MMO_JoustingGoat.mesh.JoustingGoat_Physics_01',mAnimSet=AnimSet'MMO_JoustingGoat.Anim.JoustingGoat_Anim_01',mAnimTree=AnimTree'MMO_JoustingGoat.Anim.JoustingGoat_Animtree',mMaterials=(Material'MMO_JoustingGoat.Materials.Horse_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=40.f,Y=98.f),mBiteBoneName=Jaw))
	mFullMeshes.Add((mName="Lavahorse",mSkeletalMesh=SkeletalMesh'MMO_JoustingGoat.mesh.Horse_01',mPhysicsAsset=PhysicsAsset'MMO_JoustingGoat.mesh.JoustingGoat_Physics_01',mAnimSet=AnimSet'MMO_JoustingGoat.Anim.JoustingGoat_Anim_01',mAnimTree=AnimTree'MMO_JoustingGoat.Anim.JoustingGoat_Animtree',mMaterials=(Material'MMO_JoustingGoat.Materials.Horse_Mat_02'),mTranslation=(Z=8.f),mCollisionCylinder=(X=40.f,Y=98.f),mBiteBoneName=Jaw))
	mFullMeshes.Add((mName="Donkey",mSkeletalMesh=SkeletalMesh'MMO_Donkey.mesh.Donkey_01',mPhysicsAsset=PhysicsAsset'MMO_Donkey.mesh.Donkey_Physics_01',mAnimSet=AnimSet'MMO_Donkey.Anim.Donkey_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'MMO_Donkey.Materials.Donkey_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f),mAnimationNames=(,,Baa),mBiteBoneName=bone6))
	mFullMeshes.Add((mName="Pig",mSkeletalMesh=SkeletalMesh'MMO_Pig.mesh.Pig_01',mPhysicsAsset=PhysicsAsset'MMO_Pig.mesh.Pig_Physics_01',mAnimSet=AnimSet'MMO_Pig.Anim.Pig_Anim_01',mAnimTree=AnimTree'Characters.Anim.Characters_Animtree_01',mMaterials=(Material'MMO_Pig.Materials.Pig_Mat_01'),mTranslation=(Z=-12.f),mCollisionCylinder=(X=25.f,Y=30.f),mScale=3.f,mAnimationNames=(Graze,Walk,Scratch)))
	mFullMeshes.Add((mName="Cat",mSkeletalMesh=SkeletalMesh'Heist_CatCircle.mesh.Cat_01',mPhysicsAsset=PhysicsAsset'Heist_CatCircle.mesh.Cat_Physics_01',mAnimSet=AnimSet'Heist_CatCircle.Anim.Cat_Anim_01',mAnimTree=AnimTree'Characters.Anim.Characters_Animtree_01',mMaterials=(MaterialInstanceConstant'Heist_CatCircle.Materials.Cat_Mat_01'),mTranslation=(Z=-45.f),mCollisionCylinder=(X=25.f,Y=30.f),mScale=1.3f,mAnimationNames=(,,ToranRa_01),mBiteBoneName=Head))
	mFullMeshes.Add((mName="Chihuahua",mSkeletalMesh=SkeletalMesh'Goat_Zombie.Meshes.Chihuahua_Rigged_01',mPhysicsAsset=PhysicsAsset'Goat_Zombie.Meshes.Chihuahua_Rigged_01_Physics',mAnimSet=none,mAnimTree=none,mMaterials=(Material'Goat_Zombie.Materials.Chihuahua_Mat_01'),mTranslation=(Z=-5.f),mCollisionCylinder=(X=25.f,Y=30.f),mBiteBoneName=Head))
	//Birds
	mFullMeshes.Add((mName="Dodo",mSkeletalMesh=SkeletalMesh'MMO_Dodo.mesh.Dodo_01',mPhysicsAsset=PhysicsAsset'MMO_Dodo.mesh.Dodo_Physics_01',mAnimSet=AnimSet'MMO_Dodo.Anim.Dodo_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'MMO_Dodo.Materials.Dodo_Mat_01'),mTranslation=(Z=-32.f),mCollisionCylinder=(X=25.f,Y=30.f),mBiteBoneName=Jaw))
	mFullMeshes.Add((mName="Penguin",mSkeletalMesh=SkeletalMesh'ClassyGoat.mesh.ClassyGoat_01',mPhysicsAsset=PhysicsAsset'ClassyGoat.mesh.ClassyGoat_Physics_01',mAnimSet=AnimSet'ClassyGoat.Anim.ClassyGoat_Anim_01',mAnimTree=AnimTree'ClassyGoat.Anim.ClassyGoat_AnimTree',mMaterials=(Material'ClassyGoat.Materials.ClassyGoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=20.f,Y=35.f)))
	mFullMeshes.Add((mName="Flamingo",mSkeletalMesh=SkeletalMesh'Heist_Flamingoat.mesh.Flamingoat_01',mPhysicsAsset=PhysicsAsset'Heist_Flamingoat.mesh.Flamingoat_Physics_01',mAnimSet=AnimSet'Heist_Flamingoat.Anim.Flamingoat_Anim_01',mAnimTree=AnimTree'Heist_Flamingoat.Anim.Flamingoat_AnimTree',mMaterials=(Material'Heist_Flamingoat.Materials.Flamingoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=33.f,Y=80.f)))
	mFullMeshes.Add((mName="Ostrich",mSkeletalMesh=SkeletalMesh'FeatherGoat.mesh.FeatherGoat_01',mPhysicsAsset=PhysicsAsset'FeatherGoat.mesh.FeatherGoat_Physics_01',mAnimSet=AnimSet'FeatherGoat.Anim.FeatherGoat_Anim_01',mAnimTree=AnimTree'FeatherGoat.Anim.FeatherGoat_AnimTree',mMaterials=(Material'FeatherGoat.Materials.FeatherGoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=50.f,Y=85.f)))
	mFullMeshes.Add((mName="Dobomination",mSkeletalMesh=SkeletalMesh'MMO_Dodo.mesh.DodoAbomination_01',mPhysicsAsset=PhysicsAsset'MMO_Dodo.mesh.DodoAbomination_Physics_01',mAnimSet=AnimSet'MMO_Dodo.Anim.DodoAbomination_Anim_01',mAnimTree=AnimTree'MMO_Aborre.Anim.Aborre_AnimTree',mMaterials=(Material'MMO_Dodo.Materials.DodoAbomination_Mat_01'),mTranslation=(Z=-50.f),mCollisionCylinder=(X=100.f,Y=50.f),mBiteBoneName=Head))
	//Monsters
	mFullMeshes.Add((mName="Demon",mSkeletalMesh=SkeletalMesh'MMO_Demon.mesh.Demon_01',mPhysicsAsset=PhysicsAsset'MMO_Demon.mesh.Demon_Physics_01',mAnimSet=AnimSet'MMO_Demon.Anim.Demon_Anim_01',mAnimTree=AnimTree'MMO_Aborre.Anim.Aborre_AnimTree',mMaterials=(Material'MMO_Demon.Materials.Demon_Mat'),mTranslation=(Z=-75.f),mCollisionCylinder=(X=28.f,Y=75.f),mAnimationNames=(,Idle,Spawn),mBiteBoneName=Hand_R))
	mFullMeshes.Add((mName="Spider",mSkeletalMesh=SkeletalMesh'MMO_Spider.mesh.Spider_01',mPhysicsAsset=PhysicsAsset'MMO_Spider.mesh.Spider_Physics_01',mAnimSet=AnimSet'MMO_Spider.Anim.Spider_Anim_01',mAnimTree=AnimTree'MMO_Aborre.Anim.Aborre_AnimTree',mMaterials=(Material'MMO_Spider.Materials.Spider_Mat'),mTranslation=(Z=-50.f),mCollisionCylinder=(X=100.f,Y=50.f),mBiteBoneName=Head))
	mFullMeshes.Add((mName="Tyrannosaur",mSkeletalMesh=SkeletalMesh'MMO_OldGoat.mesh.OldGoat_01',mPhysicsAsset=PhysicsAsset'MMO_OldGoat.mesh.OldGoat_Physics_01',mAnimSet=AnimSet'MMO_OldGoat.Anim.OldGoat_Anim_01',mAnimTree=AnimTree'MMO_OldGoat.Anim.OldGoat_AnimTree',mMaterials=(Material'MMO_OldGoat.Materials.OldGoat_Mat_01'),mTranslation=(Z=20.f),mCollisionCylinder=(X=200.f,Y=250.f)))
	//Fishs
	mFullMeshes.Add((mName="Whale",mSkeletalMesh=SkeletalMesh'Whale.mesh.Whale',mPhysicsAsset=PhysicsAsset'Whale.mesh.SpermGoat_Physics',mAnimSet=none,mAnimTree=none,mMaterials=(Material'Whale.Materials.Sperm_whale_Mat'),mTranslation=(Z=-100.f),mCollisionCylinder=(X=300.f,Y=100.f)))
	mFullMeshes.Add((mName="Dolphin",mSkeletalMesh=SkeletalMesh'Heist_Dolphwheelgoat.mesh.Dolphwheelgoat_01',mPhysicsAsset=PhysicsAsset'Heist_Dolphwheelgoat.mesh.Dolphwheelgoat_01_Physics',mAnimSet=AnimSet'Heist_Dolphwheelgoat.Anim.Dolphwheelgoat_Anim_01',mAnimTree=AnimTree'Heist_Dolphwheelgoat.Anim.Dolphwheelgoat_AnimTree',mMaterials=(Material'Heist_Dolphwheelgoat.Materials.Dolphwheelgoat_Mat_02',Material'Heist_Dolphwheelgoat.Materials.Dolphwheelgoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=33.f,Y=40.f)))
	mFullMeshes.Add((mName="Aborre",mSkeletalMesh=SkeletalMesh'MMO_Aborre.mesh.Aborre_01',mPhysicsAsset=PhysicsAsset'MMO_Aborre.mesh.Aborre_Physics_01',mAnimSet=AnimSet'MMO_Aborre.Anim.Aborre_Anim_01',mAnimTree=AnimTree'MMO_Aborre.Anim.Aborre_AnimTree',mMaterials=(Material'MMO_Aborre.Materials.Aborre_Mat_01'),mTranslation=(Z=0.f),mCollisionCylinder=(X=28.f,Y=75.f)))
	//mFullMeshes.Add((mName="Fish",mSkeletalMesh=SkeletalMesh'MMO_Armor.mesh.Fish_01',mPhysicsAsset=PhysicsAsset'MMO_Armor.mesh.Fish_Physics_01',mAnimSet=none,mAnimTree=none,mMaterials=(Material'MMO_Armor.Materials.Hunter_Mat_01'),mTranslation=(Z=0.f),mCollisionCylinder=(X=25.f,Y=10.f)))
	//Exotic animals
	mFullMeshes.Add((mName="Llama",mSkeletalMesh=SkeletalMesh'Llama.Meshes.Llama_Rigged',mPhysicsAsset=PhysicsAsset'Llama.Meshes.Llama__PhysicsAsset',mAnimSet=AnimSet'Llama.Anim.Llama_Anim_01',mAnimTree=AnimTree'Llama.Anim.Llama_AnimTree',mMaterials=(Material'Llama.Materials.Llama_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=50.f,Y=60.f)))
	mFullMeshes.Add((mName="Camel",mSkeletalMesh=SkeletalMesh'Heist_Camelgoat.mesh.Camelgoat_01',mPhysicsAsset=PhysicsAsset'Heist_Camelgoat.mesh.Camelgoat_Physics_01',mAnimSet=AnimSet'Heist_Camelgoat.Anim.Camelgoat_Anim_01',mAnimTree=AnimTree'Heist_Camelgoat.Anim.Camelgoat_AnimTree',mMaterials=(Material'Heist_Camelgoat.Materials.Camel_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=38.f,Y=100.f)))
	mFullMeshes.Add((mName="Giraffe",mSkeletalMesh=SkeletalMesh'TallGoat.mesh.TallGoat_01',mPhysicsAsset=PhysicsAsset'TallGoat.mesh.TallGoat_Physics_01',mAnimSet=AnimSet'TallGoat.Anim.TallGoat_Anim_01',mAnimTree=AnimTree'TallGoat.Anim.TallGoat_AnimTree',mMaterials=(Material'TallGoat.Materials.TallGoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=60.f,Y=130.f)))
	mFullMeshes.Add((mName="Ibex",mSkeletalMesh=SkeletalMesh'Heist_Handsomegoat.mesh.Handsomegoat_01',mPhysicsAsset=PhysicsAsset'Heist_Handsomegoat.mesh.Handsomegoat_Physics_01',mAnimSet=AnimSet'Heist_Handsomegoat.Anim.Handsomegoat_Anim_01',mAnimTree=AnimTree'Heist_Handsomegoat.Anim.Handsomegoat_AnimTree',mMaterials=(Material'Heist_Handsomegoat.Materials.Handsomegoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=30.f,Y=57.f)))
	mFullMeshes.Add((mName="Elephant",mSkeletalMesh=SkeletalMesh'Goat_Zombie.Meshes.FiremanGoat_Rigged_01',mPhysicsAsset=PhysicsAsset'Goat_Zombie.Meshes.FiremanGoat_Rigged_01_Physics',mAnimSet=AnimSet'Goat_Zombie.Anim.FiremanGoat_Anim_01',mAnimTree=AnimTree'Goat_Zombie.Anim.FiremanGoat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.FiremanGoat_Eyes_01',Material'Goat_Zombie.Materials.FiremanGoat_Tusks_01',Material'Goat_Zombie.Materials.FiremanGoat_Eyes_01',Material'Goat_Zombie.Materials.FiremanGoat_Body_M',Material'Goat_Zombie.Materials.FiremanGoat_Body_M'),mTranslation=(Z=8.f),mCollisionCylinder=(X=80.f,Y=145.f)))
	//Zombie animals
	mFullMeshes.Add((mName="ZombieElephant",mSkeletalMesh=SkeletalMesh'Goat_Zombie.Meshes.FiremanGoat_Rigged_01',mPhysicsAsset=PhysicsAsset'Goat_Zombie.Meshes.FiremanGoat_Rigged_01_Physics',mAnimSet=AnimSet'Goat_Zombie.Anim.FiremanGoat_Anim_01',mAnimTree=AnimTree'Goat_Zombie.Anim.FiremanGoat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.Zombie_FiremanGoat_Eyes_01',Material'Goat_Zombie.Materials.Zombie_FiremanGoat_Tusks_01',Material'Goat_Zombie.Materials.Zombie_FiremanGoat_Eyes_01',Material'Goat_Zombie.Materials.Zombie_BattleFiremanGoat_Body_Mat_01',Material'Goat_Zombie.Materials.Zombie_BattleFiremanGoat_Body_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=80.f,Y=145.f)))
	mFullMeshes.Add((mName="ZombieOstrich",mSkeletalMesh=SkeletalMesh'FeatherGoat.mesh.FeatherGoat_01',mPhysicsAsset=PhysicsAsset'FeatherGoat.mesh.FeatherGoat_Physics_01',mAnimSet=AnimSet'FeatherGoat.Anim.FeatherGoat_Anim_01',mAnimTree=AnimTree'FeatherGoat.Anim.FeatherGoat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.Zombie_FeatherGoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=50.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombiePenguin",mSkeletalMesh=SkeletalMesh'ClassyGoat.mesh.ClassyGoat_01',mPhysicsAsset=PhysicsAsset'ClassyGoat.mesh.ClassyGoat_Physics_01',mAnimSet=AnimSet'ClassyGoat.Anim.ClassyGoat_Anim_01',mAnimTree=AnimTree'ClassyGoat.Anim.ClassyGoat_AnimTree',mMaterials=(Material'Goat_Zombie.Materials.Zombie_ClassyGoat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=20.f,Y=35.f)))
	//Bread
	mFullMeshes.Add((mName="Bread",mSkeletalMesh=SkeletalMesh'I_Am_Bread.mesh.Slice_01',mPhysicsAsset=PhysicsAsset'I_Am_Bread.mesh.Slice_01_Physics',mAnimSet=AnimSet'I_Am_Bread.Anim.Slice_Anim_01',mAnimTree=AnimTree'I_Am_Bread.Anim.Slice_AnimTree',mMaterials=(Material'I_Am_Bread.Materials.Bread_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=30.f)))
	mFullMeshes.Add((mName="Baguette",mSkeletalMesh=SkeletalMesh'I_Am_Bread.mesh.Baguette_01',mPhysicsAsset=PhysicsAsset'I_Am_Bread.mesh.Baguette_01_Physics',mAnimSet=none,mAnimTree=none,mMaterials=(Material'I_Am_Bread.Materials.Baguette_Mat_01'),mTranslation=(Z=0.f),mCollisionCylinder=(X=10.f,Y=62.f)))
	//Costume
	mFullMeshes.Add((mName="Bear",mSkeletalMesh=SkeletalMesh'MMO_Bear.mesh.Bear_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'MMO_Bear.Anim.Bear_Anim_01',mAnimTree=AnimTree'MMO_Bear.Anim.Bear_AnimTree',mMaterials=(Material'MMO_Bear.Materials.Bear_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=28.f,Y=30.f)))
	mFullMeshes.Add((mName="Snail",mSkeletalMesh=SkeletalMesh'MMO_Snail.mesh.Snail_01',mPhysicsAsset=PhysicsAsset'MMO_Snail.mesh.Snail_Physics_01',mAnimSet=AnimSet'MMO_Snail.Anim.Snail_Anim_01',mAnimTree=AnimTree'MMO_Snail.Anim.SnailTree',mMaterials=(Material'MMO_Characters.Materials.Elf_man_Mat_01',Material'goat.Materials.Goat_Mat_01'),mTranslation=(Z=8.f),mCollisionCylinder=(X=25.f,Y=5.f)))
	mFullMeshes.Add((mName="Explorer",mSkeletalMesh=SkeletalMesh'Explorer.mesh.Explorer',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Explorer.Materials.Explorer_Body_Mat_01'),mTranslation=(Z=0.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="TurdleBlue",mSkeletalMesh=SkeletalMesh'Turdle.mesh.MicahelBay_Turdle',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Turdle.Materials.Turdle_Blue'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="TurdleOrange",mSkeletalMesh=SkeletalMesh'Turdle.mesh.MicahelBay_Turdle',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Turdle.Materials.Turdle_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="TurdlePurple",mSkeletalMesh=SkeletalMesh'Turdle.mesh.MicahelBay_Turdle',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Turdle.Materials.Turdle_Purple'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="TurdleRed",mSkeletalMesh=SkeletalMesh'Turdle.mesh.MicahelBay_Turdle',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Turdle.Materials.Turdle_Red'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Casual girls
	mFullMeshes.Add((mName="Bride",mSkeletalMesh=SkeletalMesh'Human_Characters.Meshes.Bride_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Bride_INST_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Casualgirl",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualGirl_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.CasualGirl_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Elin",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualGirl_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Elin_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="FortuneTeller",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Fortuneteller_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Line",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualGirl_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Line_Dif_01_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Marie",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualGirl_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Marie_Dif_01_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Moa",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualGirl_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Moa_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Casual men
	mFullMeshes.Add((mName="Anton",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Anton_Dif_01_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Armin",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Armin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Bartek",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Bartek_TaBort_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Bodyguard",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Bodyguard_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Businessman",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Businessman_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Chainsawman",mSkeletalMesh=SkeletalMesh'Human_Characters.Meshes.Chainsaw_Man',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Chainsaw_Body_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ConradORien",mSkeletalMesh=SkeletalMesh'Human_Characters.Meshes.ConradORien',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Conrad_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Worker",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.ConstructionWorker_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Deadmau5",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Deadmau5_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Francis",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Francis_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Governor",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Governor_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Groom",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Groom_INST_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="GSTFS",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.GSTFS_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="JSjoo",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.J_Sjoo_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Joel",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Joel_Dif_01_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Jolle",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Jolle_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="KA",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.KA_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Kenny",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Kenny_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Molle",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Molle_Dif_01_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Ocke",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Ocke_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Oliver",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Oliver_INST_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paul",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Paul_Dif_01_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Philip",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Philip_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="RonaldHump",mSkeletalMesh=SkeletalMesh'Human_Characters.Meshes.RonaldHump',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.RonaldHump_INST_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Santi",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Santi_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Sebbe",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Sebbe_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Souny",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.SounySama_INST_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="SportyMan",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.SportyMan_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Stefan",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Stefan_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Stek",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Stek_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="SurvivalCaracter",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Human_Characters.Materials.M_Survival_Character_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Wassse",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Characters.Materials.Wassse_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="William",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.William_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Zipper",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Zipper_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Peasant wemen
	mFullMeshes.Add((mName="Peasantwoman1",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_Woman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Woman_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasantwoman2",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_Woman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Woman_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasantwoman3",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_Woman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Woman_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasantwoman4",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_Woman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Woman_Mat_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasantwoman5",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_Woman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Woman_Mat_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasantwoman6",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_Woman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Woman_Mat_06'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasantwoman7",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_Woman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Woman_Mat_07'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasantwoman8",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_Woman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Woman_Mat_08'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasantwoman9",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_Woman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Woman_Mat_09'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Peasant men
	mFullMeshes.Add((mName="Peasant1",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Mat_01a'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasant2",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasant3",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasant4",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Mat_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasant6",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Mat_06'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasant7",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Mat_07'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasant8",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Mat_08'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasant9",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Mat_09'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasant10",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Mat_10'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Peasant11",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Peasant_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Peasant_Mat_11'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Woodsmen
	mFullMeshes.Add((mName="Woodsman1",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Woodsman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Woodsman_Mat_01a'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Woodsman2",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Woodsman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Woodsman_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Woodsman3",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Woodsman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Woodsman_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Woodsman4",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Woodsman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Woodsman_Mat_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Woodsman5",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Woodsman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Woodsman_Mat_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Woodsman6",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Woodsman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Woodsman_Mat_06'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Woodsman7",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Woodsman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Woodsman_Mat_07'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Woodsman8",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Woodsman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Woodsman_Mat_08'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Woodsman9",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Woodsman_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Woodsman_Mat_09'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Knight wemen
	mFullMeshes.Add((mName="Knightwoman1",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_Female_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Female_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knightwoman2",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_Female_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Female_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knightwoman3",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_Female_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Female_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knightwoman4",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_Female_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Female_Mat_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knightwoman5",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_Female_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Female_Mat_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knightwoman6",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_Female_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Female_Mat_06'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Knight men
	mFullMeshes.Add((mName="Knight1",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'MMO_Characters.Materials.Character_MASTER_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knight2",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knight3",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knight4",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Mat_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knight5",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Mat_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knight6",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Mat_06'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knight7",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Mat_07'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knight8",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Mat_08'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knight9",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Mat_09'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knight10",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Mat_10'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Knight11",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Knight_Mat_11'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Elves female
	mFullMeshes.Add((mName="Elfwoman1",mSkeletalMesh=SkeletalMesh'MMO_Elfs.mesh.Elf_Female_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Elf_Female_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Elfwoman3",mSkeletalMesh=SkeletalMesh'MMO_Elfs.mesh.Elf_Female_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Elf_Female_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Elfwoman4",mSkeletalMesh=SkeletalMesh'MMO_Elfs.mesh.Elf_Female_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Elf_Female_Mat_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Elfwoman5",mSkeletalMesh=SkeletalMesh'MMO_Elfs.mesh.Elf_Female_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Elf_Female_Mat_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Elfwoman6",mSkeletalMesh=SkeletalMesh'MMO_Elfs.mesh.Elf_Female_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.Elf_Female_Mat_06'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Elves male
	mFullMeshes.Add((mName="Elf",mSkeletalMesh=SkeletalMesh'MMO_Elfs.mesh.Elf_Man_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'MMO_Characters.Materials.Elf_man_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Special MMO characters
	mFullMeshes.Add((mName="King",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Knight_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'MMO_Characters.Materials.King_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Priest",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Priest',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'MMO_Characters.Materials.Priest_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Dumbledoor",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Dumbledoor',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'MMO_Characters.Materials.Beard_Mat_01',Material'MMO_Characters.Materials.Dumbledoor'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Dwarf",mSkeletalMesh=SkeletalMesh'MMO_Characters.mesh.Dwarf_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'MMO_Characters.Materials.Dwarf_Mat_01'),mTranslation=(Z=-170.f),mCollisionCylinder=(X=25.f,Y=85.f),mScale=0.5f))
	mFullMeshes.Add((mName="Genie",mSkeletalMesh=SkeletalMesh'MMO_Genie.mesh.Genie_01',mPhysicsAsset=PhysicsAsset'MMO_Genie.mesh.Genie_Physics_01',mAnimSet=AnimSet'MMO_Genie.Anim.Genie_Anim_01',mAnimTree=AnimTree'Characters.Anim.Characters_Animtree_01',mMaterials=(Material'MMO_Genie.Materials.Genie_Mat_01',Material'MMO_Genie.Materials.Cloud_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f),mAnimationNames=(,Idle,),mBiteBoneName=Cloud))
	mFullMeshes.Add((mName="Goast",mSkeletalMesh=SkeletalMesh'Goast.mesh.Goast_01',mPhysicsAsset=PhysicsAsset'Goast.Mesh.Goast_Physics_01',mAnimSet=AnimSet'Goast.Anim.Goast_Anim_01',mAnimTree=AnimTree'Goast.Anim.Goast_AnimTree',mMaterials=(Material'Goast.Materials.Goast_Mat_01',MaterialInstanceConstant'Goast.Materials.Goast_Mat_01_INST',Material'Goast.Materials.Goast_Mat_02'),mTranslation=(Z=8.f),mCollisionCylinder=(X=30.f,Y=62.f)))
	//Zombie wemen
	mFullMeshes.Add((mName="ZombieBride",mSkeletalMesh=SkeletalMesh'Human_Characters.Meshes.Bride_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Bride_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieElin",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualGirl_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Elin_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieFortuneTeller",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Fortuneteller_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieLine",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualGirl_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Line_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieMarie",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualGirl_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Marie_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieMoa",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualGirl_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Moa_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieWaitress",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualGirl_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Waitress_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Zombie men
	mFullMeshes.Add((mName="ZombieAnton",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Anton_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieArmin",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Armin_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieBartek",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Bartek_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieBodyguard",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Bodyguard_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieBodyguard2",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Bodyguard_RED_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieBusinessman",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Businessman_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieConradORien",mSkeletalMesh=SkeletalMesh'Human_Characters.Meshes.ConradORien',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Conrad_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieWorker",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Constructionworker_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieGovernor",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Governor_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieGroom",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Groom_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieGSTFS",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_GSTFS_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieJSjoo",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_J_Sjoo_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieJoel",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Joel_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieJolle",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Jolle_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieKA",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_KA_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieMolle",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Molle_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieOcke",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Ocke_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieOliver",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Oliver_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombiePaul",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Paul_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombiePhilip",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Philip_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieRonaldHump",mSkeletalMesh=SkeletalMesh'Human_Characters.Meshes.RonaldHump',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_RonaldHump_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieSanti",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Santi_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieSebbe",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Sebbe_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieSonny",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Sonny_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieStefan",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Stefan_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieStek",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Stek_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieWasse",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Wasse_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieWilliam",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_William_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="ZombieZipper",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Zombie_Characters.Materials.Zombie_Zipper_INST'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Heist wemen
	mFullMeshes.Add((mName="Paydaywoman1",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Clothes_Mat_01',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman2",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Clothes_Mat_02',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman3",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Clothes_Mat_03',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman4",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Clothes_Mat_04',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman5",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Clothes_Mat_05',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman6",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Clothes_Mat_06',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman7",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Clothes_Mat_07',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman8",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Clothes_Mat_08',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman9",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Clothes_Mat_09',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman10",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Clothes_Mat_10',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman11",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Clothes_Mat_11',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman12",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Clothes_Mat_12',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_01.Female_01_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman21",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_01',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman22",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_02',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman23",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_03',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman24",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_04',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman25",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_05',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman26",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_06',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman27",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_07',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_07'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman28",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_08',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman29",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_09',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman30",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_10',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman31",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_11',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman32",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_12',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman33",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_13',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_06'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydaywoman34",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Female_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Clothes_Mat_14',MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_07'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Heist men
	mFullMeshes.Add((mName="Paydayman1",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Clothes_Mat_01',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman2",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Clothes_Mat_02',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman3",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Clothes_Mat_03',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman4",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Clothes_Mat_04',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman5",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Clothes_Mat_05',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman6",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Clothes_Mat_06',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman7",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Clothes_Mat_07',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman8",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Clothes_Mat_08',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman9",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Clothes_Mat_09',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman10",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Clothes_Mat_10',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman11",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Clothes_Mat_11',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman21",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_01',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman22",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_02',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman23",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_03',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman24",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_04',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman25",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_05',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman26",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_06',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman27",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_07',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman28",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_08',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman29",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_09',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman30",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_10',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman31",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_11',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman32",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_12',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman33",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_13',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Paydayman34",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Male_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Clothes_Mat_14',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Heist special
	mFullMeshes.Add((mName="Musician",mSkeletalMesh=SkeletalMesh'Heist_Characters_01.mesh.Heist_Streetmusician_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Female_02.Female_02_Skin_Mat_02',MaterialInstanceConstant'Heist_Characters_01.Materials.Musician.Streetmusician_Clothes_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Cop1",mSkeletalMesh=SkeletalMesh'Heist_Characters_02.mesh.Cop_01',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_02.Materials.Cops_Skin_Mat_01',MaterialInstanceConstant'Heist_Characters_02.Materials.Cops_Clothes_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Cop2",mSkeletalMesh=SkeletalMesh'Heist_Characters_02.mesh.Cop_02',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_02.Materials.Cops_Clothes_Mat_01',MaterialInstanceConstant'Heist_Characters_02.Materials.Cops_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Bob",mSkeletalMesh=SkeletalMesh'Heist_Characters_02.mesh.Heist_Bob',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_02.Materials.Bob_Clothes_Mat_01',MaterialInstanceConstant'Heist_Characters_02.Materials.Bob_Head_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Chains",mSkeletalMesh=SkeletalMesh'Heist_Characters_02.mesh.Heist_Chains',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_02.Materials.Chains_Head_Mat_01',MaterialInstanceConstant'Heist_Characters_02.Materials.Chains_Clothes_Mat_01',MaterialInstanceConstant'Heist_Characters_02.Materials.Criminals_Hands_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Dallas",mSkeletalMesh=SkeletalMesh'Heist_Characters_02.mesh.Heist_Dallas',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_02.Materials.Dallas_Head_Mat_01',MaterialInstanceConstant'Heist_Characters_02.Materials.Dallas_Clothes_Mat_01',MaterialInstanceConstant'Heist_Characters_02.Materials.Criminals_Hands_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Hoxton",mSkeletalMesh=SkeletalMesh'Heist_Characters_02.mesh.Heist_Hoxton',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_02.Materials.Hoxton_Head_Mat_01',MaterialInstanceConstant'Heist_Characters_02.Materials.Hoxton_Clothes_Mat_01',MaterialInstanceConstant'Heist_Characters_02.Materials.Criminals_Hands_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Wolf",mSkeletalMesh=SkeletalMesh'Heist_Characters_02.mesh.Heist_Wolf',mPhysicsAsset=PhysicsAsset'Heist_Characters_01.mesh.HeistNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_02.Materials.Wolf_Head_Mat_01',MaterialInstanceConstant'Heist_Characters_02.Materials.Wolf_Clothes_Mat_01',MaterialInstanceConstant'Heist_Characters_02.Materials.Criminals_Hands_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Space wemen
	mFullMeshes.Add((mName="Guidewoman",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Office_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Fem01_Skin_01',MaterialInstanceConstant'Space_Characters.Materials.Guide_Fem_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Officewoman",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Office_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Fem01_Skin_02',MaterialInstanceConstant'Space_Characters.Materials.Office_Fem_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Servicewoman",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Office_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Fem01_Skin_03',MaterialInstanceConstant'Space_Characters.Materials.Service_Fem_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Space men
	mFullMeshes.Add((mName="Guideman",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Guide_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Guide_Male_01',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Officeman",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Office_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Heist_Characters_01.Materials.Male_02.Male_02_Skin_Mat_01',MaterialInstanceConstant'Space_Characters.Materials.Office_Male_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Serviceman",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Guide_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Service_Male_01',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="SecurityGuard",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Guide_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SecurityGuard_01',MaterialInstanceConstant'Heist_Characters_01.Materials.Male_01.Male_01_Skin_Mat_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Space badehaus
	mFullMeshes.Add((mName="Badehaus1",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_BathingSuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Badehaus_Skin_01',MaterialInstanceConstant'Space_Characters.Materials.Badehaus_Body_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Badehaus2",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_BathingSuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Badehaus_Skin_02',MaterialInstanceConstant'Space_Characters.Materials.Badehaus_Body_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Badehaus3",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_BathingSuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Badehaus_Skin_03',MaterialInstanceConstant'Space_Characters.Materials.Badehaus_Body_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Gym",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_BathingSuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Badehaus_Skin_04',MaterialInstanceConstant'Space_Characters.Materials.GymOutfit_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Spacesuit wemen
	mFullMeshes.Add((mName="Spacesuitwoman1",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem02_Gloves_01',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman2",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem02_Gloves_02',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman3",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem02_Gloves_03',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman4",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem02_Gloves_04',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman5",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem02_Gloves_05',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman6",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem02_Gloves_06',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_06'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman7",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem02_Gloves_07',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_07'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman8",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem02_Gloves_02',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_08'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman11",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem01_Gloves_01',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman12",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem01_Gloves_02',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman13",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem01_Gloves_03',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman14",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem01_Gloves_04',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman15",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem01_Gloves_05',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman16",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem01_Gloves_06',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_06'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman17",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem01_Gloves_07',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_07'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman18",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem01_Gloves_08',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_08'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman19",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem03_Gloves_01',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman20",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem03_Gloves_02',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitwoman21",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Fem03_Gloves_03',MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Fem_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Spacesuit men
	mFullMeshes.Add((mName="Spacesuitman1",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_01',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male01_Gloves_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman2",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_02',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male01_Gloves_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman3",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_03',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male01_Gloves_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman4",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_04',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male01_Gloves_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman5",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_05',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male01_Gloves_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman6",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_06',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male01_Gloves_06'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman7",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_08',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male01_Gloves_07'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman8",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_09',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male02_Gloves_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman9",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_10',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male02_Gloves_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman10",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_03',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male02_Gloves_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman11",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_04',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male02_Gloves_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman21",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_01',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male03_Gloves_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman22",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_02',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male03_Gloves_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman23",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_03',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male03_Gloves_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman24",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_04',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male03_Gloves_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman25",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_05',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male03_Gloves_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman26",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_06',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male03_Gloves_06'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman27",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_08',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male04_Gloves_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman28",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_09',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male04_Gloves_02'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman29",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_10',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male04_Gloves_03'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman30",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_03',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male04_Gloves_04'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman31",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_04',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male04_Gloves_05'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesuitman32",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.SpaceSuit_Male_05',MaterialInstanceConstant'Space_Characters.Materials.Skin_Gloves_Male04_Gloves_06'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Space special
	mFullMeshes.Add((mName="TeenMoa",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualGirl_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Space_BottleRockets.Materials.TeenMoa_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="TeenSanti",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Space_BottleRockets.Materials.TeenSanti_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Astronaut",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Space_Museum.Materials.Astronaut_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="AnimalLover",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters_02.Materials.Romance_AnimalLover_Face_01',MaterialInstanceConstant'Space_Characters_02.Materials.Romance_AnimalLover_Body_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Brony",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Office_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters_02.Materials.Romance_Brony_Face_01',MaterialInstanceConstant'Space_Characters_02.Materials.Romance_Brony_Body_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="CandyLover",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_BathingSuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters_02.Materials.Romance_Candylover_Face_01',MaterialInstanceConstant'Space_Characters_02.Materials.Romance_CandyLover_Body_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="CrazyPerson",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters_02.Materials.Romance_CrazyPerson_Face_01',MaterialInstanceConstant'Space_Characters_02.Materials.Romance_CrazyPerson_Body_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Prisoner1",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Fem02_Skin_01',MaterialInstanceConstant'Space_Characters_02.Materials.Prisoner_Fem_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Prisoner2",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Fem01_Skin_01',MaterialInstanceConstant'Space_Characters_02.Materials.Prisoner_Fem_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="TestSubject1",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Fem02_Skin_01',MaterialInstanceConstant'Space_Characters_02.Materials.TestSubject_Fem_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="TestSubject2",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Fem01_Skin_01',MaterialInstanceConstant'Space_Characters_02.Materials.TestSubject_Fem_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="TestSubject3",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters_02.Materials.TestSubject_Male_01',MaterialInstanceConstant'Space_Characters.Materials.Skin_Male01_Skin_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="TestSubject4",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters_02.Materials.TestSubject_Male_01',MaterialInstanceConstant'Space_Characters.Materials.Skin_Male02_Skin_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="SpaceWorker1",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Fem02_Skin_01',MaterialInstanceConstant'Space_Characters.Materials.ConstructionWorker_Fem_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="SpaceWorker2",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Skin_Fem01_Skin_01',MaterialInstanceConstant'Space_Characters.Materials.ConstructionWorker_Fem_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="SpaceWorker3",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.ConstructionWorker_Male_01',MaterialInstanceConstant'Space_Characters.Materials.Skin_Male01_Skin_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="SpaceWorker4",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.ConstructionWorker_Male_01',MaterialInstanceConstant'Space_Characters.Materials.Skin_Male02_Skin_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Dancer1",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Dancer_Male_01',MaterialInstanceConstant'Space_Characters.Materials.Skin_Male01_Skin_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Dancer2",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_02',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters.Materials.Dancer_Male_01',MaterialInstanceConstant'Space_Characters.Materials.Skin_Male02_Skin_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Ghoul1",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Fem_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters_02.Materials.Ghoul_Fem_Face_01',MaterialInstanceConstant'Space_Characters_02.Materials.Ghoul_Fem_Body_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Ghoul2",mSkeletalMesh=SkeletalMesh'Space_Characters.mesh.Male_Jumpsuit_01',mPhysicsAsset=PhysicsAsset'Space_Characters.Anim.SpaceNPC_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Space_Characters_02.Materials.Ghoul_Male_Body_01',MaterialInstanceConstant'Space_Characters_02.Materials.Ghoul_Male_Face_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	//Robots
	mFullMeshes.Add((mName="ChihuahuaTurret",mSkeletalMesh=SkeletalMesh'Goat_Zombie.Meshes.Chihuahua_Rigged_01',mPhysicsAsset=PhysicsAsset'Goat_Zombie.Meshes.Chihuahua_Rigged_01_Physics',mAnimSet=none,mAnimTree=none,mMaterials=(Material'Space_Portal.Materials.chihuahua_turret_df_Mat'),mTranslation=(Z=-5.f),mCollisionCylinder=(X=25.f,Y=30.f),mBiteBoneName=Head))
	mFullMeshes.Add((mName="RobotCleaner",mSkeletalMesh=SkeletalMesh'Space_Droids.Meshes.RobotCleaning_Rig_01',mPhysicsAsset=PhysicsAsset'Space_Droids.Meshes.RobotCleaning_PhysAsset',mAnimSet=AnimSet'Space_Droids.Meshes.RobotCleaning_Anim_01',mAnimTree=AnimTree'Space_Droids.Anim.Robot_Animtree_01',mMaterials=(MaterialInstanceConstant'Space_Droids.Materials.InfoDroid_INST_02',Material'Space_Droids.Materials.Robots_Mat',Material'Space_BottleRockets.Materials.BottleRocketWater_Mat_01',Material'Space_BottleRockets.Materials.BottleRocket_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="RobotDispenser",mSkeletalMesh=SkeletalMesh'Space_Droids.Meshes.RobotCandisp_Rig_01',mPhysicsAsset=PhysicsAsset'Space_Droids.Meshes.RobotCandisp_PhysAsset_01',mAnimSet=AnimSet'Space_Droids.Meshes.RobotCandisp_Anim_01',mAnimTree=AnimTree'Space_Droids.Anim.Robot_Animtree_01',mMaterials=(MaterialInstanceConstant'Space_Droids.Materials.InfoDroid_INST_01',Material'Food.Materials.Props_Can_Bottle_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="RobotHealer",mSkeletalMesh=SkeletalMesh'Space_Droids.Meshes.RobotDefib_Rig_01',mPhysicsAsset=PhysicsAsset'Space_Droids.Meshes.RobotDefib_PhysAsset_01',mAnimSet=AnimSet'Space_Droids.Meshes.RobotDefib_Anim_01',mAnimTree=AnimTree'Space_Droids.Anim.Robot_Animtree_01',mMaterials=(MaterialInstanceConstant'Space_Droids.Materials.InfoDroid_INST_03',Material'Space_Droids.Materials.Robots_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="RobotInformer",mSkeletalMesh=SkeletalMesh'Space_Droids.Meshes.RobotInfo_Rig_01',mPhysicsAsset=PhysicsAsset'Space_Droids.Meshes.RobotInfo_PhysAsset_01',mAnimSet=AnimSet'Space_Droids.Meshes.RobotInfo_Anim_01',mAnimTree=AnimTree'Space_Droids.Anim.Robot_Animtree_01',mMaterials=(MaterialInstanceConstant'Space_Droids.Materials.InfoDroid_Mat_05',Material'Space_Droids.Materials.Droid_Icon_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="RobotPainter",mSkeletalMesh=SkeletalMesh'Space_Droids.Meshes.RobotPainter_Rig_01',mPhysicsAsset=PhysicsAsset'Space_Droids.Meshes.RobotPainter_PhysAsset_01',mAnimSet=AnimSet'Space_Droids.Meshes.RobotPainter_Anim_01',mAnimTree=AnimTree'Space_Droids.Anim.Robot_Animtree_01',mMaterials=(MaterialInstanceConstant'Space_Droids.Materials.InfoDroid_INST_04',Material'Space_Droids.Materials.Robots_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="G2",mSkeletalMesh=SkeletalMesh'CH_G2_Playable.mesh.G2_Playable_Mesh',mPhysicsAsset=PhysicsAsset'CH_G2_Playable.mesh.G2_Playable_Physics',mAnimSet=AnimSet'CH_G2_Playable.mesh.G2_Playable_Anim',mAnimTree=AnimTree'CH_G2_Playable.Anim.G2_Playable_AnimTree',mMaterials=(Material'CH_G2_Playable.mesh.G2_Playable_Mat',Material'CH_G2_Playable.mesh.G2_Playable_Face_Mat'),mTranslation=(Z=16.f),mCollisionCylinder=(X=40.f,Y=50.f)))
	mFullMeshes.Add((mName="Microwave",mSkeletalMesh=SkeletalMesh'MMO_Microwave.mesh.Microwave_01',mPhysicsAsset=PhysicsAsset'MMO_Microwave.mesh.Microwave_Physics_01',mAnimSet=AnimSet'MMO_Microwave.Anim.Microwave_Anim_01',mAnimTree=AnimTree'MMO_Microwave.Anim.Microwave_AnimTree',mMaterials=(Material'MMO_Microwave.Materials.Microwave_Mat'),mTranslation=(Z=8.f),mCollisionCylinder=(X=30.f,Y=60.f)))
	mFullMeshes.Add((mName="Shredder",mSkeletalMesh=SkeletalMesh'MMO_Shredder.mesh.Shredder',mPhysicsAsset=PhysicsAsset'MMO_Shredder.mesh.Shredder_Physics_01',mAnimSet=AnimSet'MMO_Shredder.Anim.Shredder_Anim_01',mAnimTree=AnimTree'MMO_Aborre.Anim.Aborre_AnimTree',mMaterials=(Material'MMO_Shredder.Materials.Shredder_Mat_02',Material'MMO_Shredder.Materials.Shredder_Mat_01'),mTranslation=(Z=-75.f),mCollisionCylinder=(X=100.f,Y=75.f),mAnimationNames=(,Idle,)))
	//Aliens
	mFullMeshes.Add((mName="HeadBobber",mSkeletalMesh=SkeletalMesh'CH_HeadBobber.mesh.HeadBobber_01',mPhysicsAsset=PhysicsAsset'CH_HeadBobber.mesh.HeadBobber_Physics_01',mAnimSet=AnimSet'CH_HeadBobber.Anim.HeadBobber_Anim_01',mAnimTree=AnimTree'CH_HeadBobber.AnimTree.Creature_AnimTree',mMaterials=(Material'CH_HeadBobber.Materials.SpaceGoat_Mat'),mTranslation=(Z=8.f),mCollisionCylinder=(X=60.f,Y=130.f)))
	mFullMeshes.Add((mName="Xenogoat",mSkeletalMesh=SkeletalMesh'Space_SanctumCharacters.CH_Runner_Mommy.runner_mommy',mPhysicsAsset=PhysicsAsset'Space_SanctumCharacters.Anim.Runner_Physics',mAnimSet=AnimSet'Space_SanctumCharacters.Anim.Runner_Mommy_Anim_01',mAnimTree=AnimTree'Characters.Anim.Characters_Animtree_01',mMaterials=(Material'Space_SanctumCharacters.CH_Runner_Mommy.Runner_Mommy_Mat_01'),mTranslation=(Z=-20.f),mCollisionCylinder=(X=45.f,Y=60.f),mBiteBoneName=Jaw))
	mFullMeshes.Add((mName="Headhugger",mSkeletalMesh=SkeletalMesh'Space_DarkQueen_Goat.Meshes.Headhugger',mPhysicsAsset=PhysicsAsset'Space_DarkQueen_Goat.Meshes.Headhugger_Physics',mAnimSet=none,mAnimTree=none,mMaterials=(Material'Space_DarkQueen_Goat.Materials.Headhugger_df_Mat'),mTranslation=(Z=0.f),mCollisionCylinder=(X=25.f,Y=5.f),mBiteBoneName=Root))
	mFullMeshes.Add((mName="Medusa",mSkeletalMesh=SkeletalMesh'Space_Vendors.Meshes.AlienThing',mPhysicsAsset=PhysicsAsset'Space_Vendors.Meshes.AlienThing_PhysicsAsset',mAnimSet=none,mAnimTree=none,mMaterials=(Material'Space_Vendors.Materials.AlienThing_Mat'),mTranslation=(Z=0.f),mCollisionCylinder=(X=10.f,Y=20.f),mBiteBoneName=Root))
	mFullMeshes.Add((mName="Alien",mSkeletalMesh=SkeletalMesh'Human_Characters.mesh.Alien_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualGirl_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Human_Characters.Textures.Alien_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Slender",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.Slender_INST_Mat_01'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Glitch",mSkeletalMesh=SkeletalMesh'Characters.mesh.CasualMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.CasualMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(Material'Zombie_Characters.Materials.TheGlitch_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
	mFullMeshes.Add((mName="Spacesheep",mSkeletalMesh=SkeletalMesh'MMO_Sheep.mesh.Sheep_01',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'Space_Ranch.Materials.Sheep_Space_Mat_01'),mTranslation=(Z=0.f),mCollisionCylinder=(X=25.f,Y=30.f),mBiteBoneName=Jaw_01))
	//Sheep
	mFullMeshes.Add((mName="Sheep",mSkeletalMesh=SkeletalMesh'MMO_Sheep.mesh.Sheep_01',mPhysicsAsset=PhysicsAsset'goat.mesh.goat_Physics',mAnimSet=AnimSet'goat.Anim.Goat_Anim_01',mAnimTree=AnimTree'goat.Anim.Goat_AnimTree',mMaterials=(Material'MMO_Sheep.Materials.Sheep_Dif_Mat_01'),mTranslation=(Z=0.f),mCollisionCylinder=(X=25.f,Y=30.f),mBiteBoneName=Jaw_01))
	//Survivor
	mFullMeshes.Add((mName="Survivor",mSkeletalMesh=SkeletalMesh'Characters.mesh.SportyMan_01',mPhysicsAsset=PhysicsAsset'Characters.mesh.SportyMan_Physics_01',mAnimSet=AnimSet'Heist_Characters_01.Anim.Heist_Characters_Anim_01',mAnimTree=AnimTree'Heist_Characters_01.Anim.Heist_Characters_AnimTree',mMaterials=(MaterialInstanceConstant'Human_Characters.Materials.RussianMan_INST_Mat'),mTranslation=(Z=-85.f),mCollisionCylinder=(X=25.f,Y=85.f)))
}