pragma solidity ^0.8.0;

contract Device {

    struct DeviceStruct {
        address owner; // The owner of the device
        address[] accessList; // List of addresses with access
    }
      // mutex state variable
    bool private locked;

    // mutex modifier
    modifier noReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    // Mapping to store the CID of a user based on their username
    mapping(string => string) public userToIPFS;
    mapping(address => User) public users;  // Mapping to track user details
    mapping(address => string) public addressToUsername; // Map addresses to usernames

     // Mapping from unique device ID to its DeviceStruct
    mapping(uint256 => DeviceStruct) private devices;

    mapping(address => uint256[]) private ownerToDeviceIDs;

    // Event to notify when a new device is added
    event DeviceAdded(uint256 deviceID, address owner);
     // Event to notify when a user is registered
    event UserRegistered(string username, string ipfsCID);
   
    // Event to notify when access is revoked
    event AccessRevoked(uint256 deviceID, address user);
 

    // Struct for the request details
    struct Request {
        uint256 requestID;              // Unique request ID
        address requestFromUserAddress; // The sender's address (User1)
        address requestToUserAddress;   // The recipient's address (User2)
        uint8 daysOfWeek;               // Bitmask for days
        uint256 fromDate;               // Unix timestamp for start date
        uint256 toDate;                 // Unix timestamp for end date
        uint256 deviceID;               // Device ID as a uint256 (numeric)
        bool activeFlag;                // If the request is still active
        uint256 totalTasks; 
        uint256 tasksLeft;    
        uint256 nextDueDate; // Next day number when task is due 
        uint256 _rewardAmount;

              
    }

    struct User {
        string ipfsCID;
        address userAddress;
        uint256 balance;
        int256 TotalRating;    // Renamed from 'rating'
        uint256 totalJobs;
        int256 OverallRating;  // New field for average rating
    }



    // Public array to hold all requests - viewable by anyone
    Request[] public viewRequest;

    mapping(uint256 => address[]) private deviceAccessList;

    // Mapping to track device owners (device ID => owner address)
    mapping(uint256 => address) private deviceOwners;

    uint256 private currentRequestID = 1;  // To generate unique request IDs
    uint256 private currentDeviceID = 1;  // To generate unique device IDs

    // Event to notify when access is granted to a device
    event AccessGranted(uint256 deviceID, address user);
    
    event RequestRejected(uint256 requestID, address rejectedBy);

 

    event ProgressValidated(uint256 requestID, uint256 dateNoted, uint256 completionPercentage);
    event TaskCompleted(uint256 requestID, uint256 completionDate);
    event RewardGiven(uint256 requestID, address fromUser);
    event RequestCreated(uint256 requestID, string fromUser, string toUser);
     event RatingUpdated(
        address username,
        int256 TotalRating,
        uint256 totalJobs,
        int256 OverallRating
    );
    event TokensTransferred(address from, address to, uint256 amount);

    // Register a user by their username and IPFS CID
    function registerUser(string memory _username, string memory _ipfsCID) public {
        // Ensure the user is not already registered
        require(bytes(userToIPFS[_username]).length == 0, "User already exists");

        // Store the IPFS CID associated with the username
        userToIPFS[_username] = _ipfsCID;

        users[msg.sender] = User({
            ipfsCID: _ipfsCID,
            userAddress: msg.sender,
            balance: 100,
            TotalRating: 0,    // Updated field name
            totalJobs: 0,
            OverallRating: 0   // Initialize OverallRating
        });

        // Emit event for user registration
        emit UserRegistered(_username, _ipfsCID);
    }

    // Retrieve the CID of a user based on their username
    function getUserCID(string memory _username) public view returns (string memory) {
        return userToIPFS[_username];
    }

    function addDevice(uint256 deviceID) public returns (uint256) {
        require(devices[deviceID].owner == address(0), "Device ID already exists");
        // Create a new device and store it in the mapping
        DeviceStruct storage newDevice = devices[deviceID];
        newDevice.owner = msg.sender;
        newDevice.accessList.push(msg.sender); // Add the owner to the access list
        ownerToDeviceIDs[msg.sender].push(deviceID);

        emit DeviceAdded(deviceID, msg.sender);
        return deviceID;
    }

    function getDeviceOwner(uint256 deviceID) public view returns (address) {
        require(devices[deviceID].owner != address(0), "Device does not exist");
        return devices[deviceID].owner;
    }

     function getAccessList(uint256 deviceID) public view returns (address[] memory) {
        require(devices[deviceID].owner != address(0), "Device does not exist");
        return devices[deviceID].accessList;
    }
  
    function getDevicesByOwner() public view returns (uint256[] memory) {
        return ownerToDeviceIDs[msg.sender];
    }

    // Function to send a request with task left and next due date
    function SendRequest(address _toUser, uint8 _days, uint256 _fromDate, uint256 _toDate, uint256 _deviceID, uint256 rewardAmount) public {
        // Ensure the sender is the owner of the device
        require(getDeviceOwner(_deviceID) == msg.sender, "You are not the owner of this device.");
        uint256 newRequestID = currentRequestID++; // Generate a unique request ID
        (uint256 firstDate, uint256 tasks)= calculateTotalTasks(_fromDate,_toDate,_days);
        // Add request to the list with the unique ID and set its status to Pending
        viewRequest.push(Request({
            requestID: newRequestID,
            requestFromUserAddress: msg.sender, // The sender (User1) address
            requestToUserAddress: _toUser,
            daysOfWeek: _days,
            fromDate: _fromDate,
            toDate: _toDate,
            deviceID: _deviceID,
            activeFlag: true,
            totalTasks:tasks, 
            tasksLeft:tasks,   
            nextDueDate:firstDate,
            _rewardAmount:rewardAmount
           
        }));

        
    }

    // Decode days bitmask to human-readable format
    function decodeDays(uint8 _daysOfWeek) public pure returns (string[] memory) {
        string[7] memory allDays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
        string[] memory result = new string[](7); // Maximum possible days selected (7)
        uint8 index = 0;

        // Decode each bit for each day
        for (uint8 i = 0; i < 7; i++) {
            if ((_daysOfWeek & (1 << i)) != 0) {
                result[index] = allDays[i];
                index++;
            }
        }

        // Resize the array to the actual number of days selected
        string[] memory finalResult = new string[](index);
        for (uint8 i = 0; i < index; i++) {
            finalResult[i] = result[i];
        }
        
        return finalResult;
    }

    function calculateTotalTasks(uint256 _fromDate, uint256 _toDate, uint8 _daysOfWeek) public pure returns (uint256, uint256) {
    require(_fromDate <= _toDate, "From date must be before or equal to to date");
    uint256 firstDate;
    uint256 totalTasks = 0;
    uint256 currentDate = _fromDate;
    
    while (currentDate <= _toDate) {
        // Convert timestamp to day of week (0 = Sunday, 6 = Saturday)
        uint256 dayOfWeek = (currentDate / 1 days + 4) % 7;
        
        // Check if the current day matches the selected days using bitmap
        if ((_daysOfWeek & (1 << dayOfWeek)) != 0) {
             if(totalTasks==0)
            {   
                firstDate=currentDate;
                totalTasks++;
            }
            else 
            {
                totalTasks++;
            }
        }
        
        // Move to next day
        currentDate += 1 days;
    }
    
    return (firstDate,totalTasks);
   }

    modifier onlyRequestRecipient(uint256 requestID) {
    Request storage req = _getRequestByID(requestID);
    require(msg.sender == req.requestToUserAddress, "You are not the intended recipient");
    _;
    }

    // Revoke access from a user on a specific device (except the owner)
    function revokeAccess(uint256 deviceID, address user) public {
    // Ensure the caller is the owner of the device
    //require(devices[deviceID].owner == msg.sender, "You are not the owner of this device.");
    
    // Ensure the user is not the owner
    require(user != devices[deviceID].owner, "Cannot revoke access from the owner.");

    // Find and remove the user from the access list
    uint256 length = devices[deviceID].accessList.length;
    for (uint256 i = 0; i < length; i++) {
        if (devices[deviceID].accessList[i] == user) {
            // Swap the element to be removed with the last element
            devices[deviceID].accessList[i] = devices[deviceID].accessList[length - 1];
            devices[deviceID].accessList.pop(); // Remove the last element
            emit AccessRevoked(deviceID, user);
            return;
        }
    }

    revert("User not found in access list");
}

    // Reject a request (from User 2)
    function rejectRequest(uint256 requestID) public onlyRequestRecipient(requestID) {
    // Ensure the request exists and is active
    Request storage req = _getRequestByID(requestID);
    require(req.activeFlag == true, "Request is no longer active");

    // Mark the request as rejected and deactivate it
    req.activeFlag = false;

    // Emit event for rejection if necessary
    emit RequestRejected(requestID, msg.sender);
    }



    

    // Accept a request (from User 2)
    function acceptRequest(uint256 requestID) public onlyRequestRecipient(requestID) {
        // Ensure the request exists and is active
        Request storage req = _getRequestByID(requestID);
        require(req.activeFlag == true, "Request is no longer active");


        // If the request is valid, allow User 2 to add the device access
        getAccess(req.deviceID, requestID);
    }

    function getAccess(uint256 deviceID,uint256 requestID) public onlyRequestRecipient(requestID) {
         // Ensure the device exists
        require(devices[deviceID].owner != address(0), "Device does not exist");

        // Ensure the caller is not already in the access list
        for (uint256 i = 0; i < devices[deviceID].accessList.length; i++) {
            require(devices[deviceID].accessList[i] != msg.sender, "Access already granted");
        }

        // Add the caller (msg.sender) to the access list
        devices[deviceID].accessList.push(msg.sender);

        // Emit the access granted event
        emit AccessGranted(deviceID, msg.sender);
    }


    // Private helper function to get request by ID
    function _getRequestByID(uint256 requestID) private view returns (Request storage) {
        for (uint256 i = 0; i < viewRequest.length; i++) {
            if (viewRequest[i].requestID == requestID) {
                return viewRequest[i];
            }
        }
        revert("Request not found");
    }

function getRequestsForUser() public view returns (Request[] memory) {
    uint256 requestCount = 0;

    // First, count how many requests the sender (msg.sender) is the requestToUserAddress
    for (uint256 i = 0; i < viewRequest.length; i++) {
        if (viewRequest[i].requestToUserAddress == msg.sender) {
            requestCount++;
        }
    }

    // Create a new array to hold the filtered requests
    Request[] memory userRequests = new Request[](requestCount);
    uint256 index = 0;

    // Now, add the requests to the array where msg.sender is the requestToUserAddress
    for (uint256 i = 0; i < viewRequest.length; i++) {
        if (viewRequest[i].requestToUserAddress == msg.sender) {
            userRequests[index] = viewRequest[i];
            index++;
        }
    }

    return userRequests;
}

    function validateProgress(uint256 requestID, uint256 dateNoted) public returns (uint256) {
        Request storage request = _getRequestByID(requestID);
        require(dateNoted >= request.fromDate, "Date noted is before start date");
        require(request.totalTasks > 0, "Total tasks must be greater than 0");
        require(request.tasksLeft > 0, "No tasks left to complete");

        // Task validation based on next due date
        if (dateNoted == request.nextDueDate) {
                // On-time completion
                request.tasksLeft -= 1;
                
                if (request.tasksLeft == 0) {
                    revokeAccess(request.deviceID,request.requestToUserAddress);
                    request.activeFlag = false;
                    rewardOrPenalty(requestID,request.tasksLeft);
                    emit TaskCompleted(requestID, dateNoted);
                } else {
                    request.nextDueDate = calculateNextDueDate(request.nextDueDate, request.daysOfWeek); 
                }
                uint256 progress = ((request.totalTasks - request.tasksLeft) * 100) / request.totalTasks;
                emit ProgressValidated(requestID, dateNoted, progress);
                return progress;
            } 
         else if (dateNoted > request.nextDueDate) 
         {

            if(dateNoted == request.toDate)
            {
                request.activeFlag = false;
                rewardOrPenalty(requestID,request.tasksLeft);
                revokeAccess(request.deviceID, request.requestToUserAddress);
                emit TaskCompleted(requestID, dateNoted);
                uint256 progress = ((request.totalTasks - request.tasksLeft) * 100) / request.totalTasks;
                emit ProgressValidated(requestID, dateNoted, progress);
                return progress;
            }
         }
            // else if (dateNoted > request.nextDueDate) {
            //     // Skipped dates: Validate if the dateNoted aligns with the schedule
            //     uint256 tempDueDate = request.nextDueDate;

            //     // Iterate through the schedule to find the next valid due date
            //     while (tempDueDate < dateNoted) {
            //         tempDueDate = calculateNextDueDate(tempDueDate, request.daysOfWeek);

            //         // If the dateNoted matches a valid due date in the schedule
            //         if (tempDueDate == dateNoted) {
            //             // Task is valid, deduct task
            //             request.tasksLeft -= 1;

            //             // Update the next due date
            //             request.nextDueDate = calculateNextDueDate(dateNoted, request.daysOfWeek);

            //             // Calculate and emit progress
            //             uint256 progress = ((request.totalTasks - request.tasksLeft) * 100) / request.totalTasks;
            //             emit ProgressValidated(requestID, dateNoted, progress);

            //             if(tempDueDate == request.toDate){

            //             request.taskCompletion = true;
            //             rewardOrPenalty(requestID,tasksLeft)
            //             revokeAccess(request.deviceID, request.requestToUserAddress);
            //             emit TaskCompleted(requestID, dateNoted);
            //             }

            //             return progress;
            //         }
            //     }

            //     // If no valid match is found (the dateNoted isn't in the schedule), treat it as a skipped date
            //     emit DueDateSkipped(requestID, dateNoted, request.nextDueDate);

            //     // Update the next due date based on the last processed date
            //     request.nextDueDate = calculateNextDueDate(dateNoted, request.daysOfWeek);

            //     // Calculate and return progress without deducting tasks
            //     uint256 skippedProgress = ((request.totalTasks - request.tasksLeft) * 100) / request.totalTasks;
            //     emit ProgressValidated(requestID, dateNoted, skippedProgress);
            //     return skippedProgress;
            // }

            // If the dateNoted is earlier than the nextDueDate (should never happen in this context)
            // emit DueDateSkipped(requestID, dateNoted, request.nextDueDate);
            // return ((request.totalTasks - request.tasksLeft) * 100) / request.totalTasks;
        revert("Invalid state: Progress validation failed");
    }


    function calculateNextDueDate(uint256 currentDueDay, uint8 daysBitmask) public pure returns (uint256) {
        uint8 dayOfWeek = uint8((currentDueDay + 1) % 7);
        
        for (uint8 i = 0; i < 7; i++) {
            if (daysBitmask & (1 << ((dayOfWeek + i) % 7)) != 0) {
                return currentDueDay + 1 + i;
            }
        }
        revert("No valid due date found in schedule.");
    }

    function rewardOrPenalty(uint256 requestID, uint256 _tasksLeft) internal {
        Request storage req = _getRequestByID(requestID);
        require(!req.activeFlag, "Request is still active.");

        address fromUserAddress = req.requestFromUserAddress;
        address toUserAddress = req.requestToUserAddress;

        uint256 totalTasks = req.totalTasks;
        require(totalTasks > 0, "Total tasks must be greater than zero.");
        uint256 completedTasks = totalTasks - _tasksLeft;
        require(completedTasks <= totalTasks, "Completed tasks cannot exceed total tasks.");

        uint256 rewardAmount = req._rewardAmount;
        uint256 userReward = 0;
        uint256 userPenalty = 0;

        if (completedTasks == totalTasks) {
            userReward = rewardAmount;
            updateRating(toUserAddress, 1);
        } else if (completedTasks >= (totalTasks * 70) / 100) {
            userReward = rewardAmount / 2;
            updateRating(toUserAddress, 0);
        } else {
            userPenalty = rewardAmount;
            updateRating(toUserAddress, -1);
        }

        if (userReward > 0) {
            transferTokens(fromUserAddress, toUserAddress, userReward);
        }

        if (userPenalty > 0) {
            transferTokens(toUserAddress, fromUserAddress, userPenalty);
        }
    }
     
     function transferTokens(address _from, address _to, uint256 _amount) internal noReentrant {
        require(_from != address(0), "Invalid sender address");
        require(_to != address(0), "Invalid recipient address");
        require(_amount > 0, "Amount must be greater than 0");
        require(users[_from].balance >= _amount, "Insufficient balance");
        
        // Save current balances
        uint256 fromBalance = users[_from].balance;
        uint256 toBalance = users[_to].balance;
        
        // Check for integer overflow
        require(toBalance + _amount >= toBalance, "Integer overflow");
        
        // Perform the transfer
        users[_from].balance = fromBalance - _amount;
        users[_to].balance = toBalance + _amount;

        emit TokensTransferred(_from, _to, _amount);
    }


    function updateRating(address _username, int256 _ratingChange) internal {
        User storage user = users[_username];
        user.TotalRating += _ratingChange;
        user.totalJobs += 1;

        // Calculate the OverallRating
        if (user.totalJobs > 0) {
            user.OverallRating = user.TotalRating / int256(user.totalJobs);
        } else {
            user.OverallRating = 0; // Default to 0 if no jobs completed
        }

        emit RatingUpdated(_username, user.TotalRating, user.totalJobs, user.OverallRating);
    }
    
    function getBalance(address _user) public view returns (uint256) 
    {
    require(msg.sender == _user, "You can only view your own balance.");
    return users[_user].balance;
    }
}
