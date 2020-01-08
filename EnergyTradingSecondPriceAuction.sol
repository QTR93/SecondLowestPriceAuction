pragma solidity >0.4.23 <0.7.0; // testing to return array with struct
/**
 * @title  P2P Energy trading contract for EV charging
 * @author Noureddine Lasla — nlasla@hbku.edu.qa,   2019.
 */

contract EvChargingMarket { 
    enum ContractState {NotCreated, Created, HasOffer, Established, InProgress, ReadyForPayement, ReportNotOk, Closed}
    enum AuctionState {Created, Closed, RevealEnd}
    uint [3][3] zone = [[1,2,3],[4,5,6],[7,8,9]];
    
    struct Payment {
        uint bidId;
        uint256 date;
        uint energyAmount;
        bool toPay; //or toReceive
        uint total;
    }
    
    struct SealedBid {
         address bidder;
         bytes32 bid;
    }

    struct Account { // User account
        int256 balance;
        Payment[] payments;
        bool isUser;
    }
    
   
    struct Auction {
        uint nbBid;
        SealedBid[] bids;
        AuctionState state;
    }
    
    // Auth Token
    struct AuthorizationToken{
     uint aucID;
     uint[3]zoneArea;
     bool active;
    }
    
    struct Contract {
        address buyer; // EV address
        address  seller; // Winner EP address
        uint  amount;
        uint  buyerMaxPrice;
        uint  currentPrice;
        bool  buyerMeterReport;
        bool  sellerMeterReport; 
        uint256  deliveryTime;
        uint256  auctionTimeOut;
        uint  deliveryLocation;
        uint8[] zoneArea;
        uint progress; // progress amount
        uint[] padsLocation; // location of pads charged EV
        ContractState state;       
    }

    modifier auctionNotClosed(uint _aucId) {
        require(auctions[_aucId].state  == AuctionState.Created);
        _;
    }
    
    modifier auctionClosed(uint _aucId) {
        require(auctions[_aucId].state == AuctionState.Closed);
        _;
    }
    
    modifier revealNotEnded(uint _aucId) {
        require(auctions[_aucId].state != AuctionState.RevealEnd);
        _;
    }
    
    modifier auctionExisit(uint _aucId) {
        require(contracts[_aucId].state != ContractState.NotCreated);
        _;
    }

    modifier auctionTimeOut(uint _aucId) {
        require(contracts[_aucId].auctionTimeOut > now);
        _;
    }

    modifier contractEstablished(uint _aucId) {
        require(contracts[_aucId].state == ContractState.Established);
        _;
    }

    modifier reportsOk(uint _aucId) {
        require(contracts[_aucId].sellerMeterReport);
        require(contracts[_aucId].buyerMeterReport);
        _;
    }

    modifier buyerOnly(uint _aucId) {
        require(contracts[_aucId].buyer == msg.sender);
        _;
    }

    modifier sellerOnly(uint _aucId) {
        require(contracts[_aucId].seller == msg.sender);
        _;
    }

    modifier accountExist(address _user) {
        require(accounts[_user].isUser);
        _;
    }
    modifier tokenExisit (){
        require(tokens[msg.sender].active == true);
        _;
    }
    
    uint public totalAuction;
    // map token to User
    mapping (address => AuthorizationToken)tokens;
    mapping (uint => Contract) public contracts;
    mapping (uint => Auction)  auctions;
    mapping (address => Account) public accounts;

    event LogReqCreated(address buyer, uint _aucId, uint _maxPrice, uint _amount, uint256 _time, uint256 _auctionTime, uint _location);
    event LowestBidDecreased (address _seller, uint _aucId, uint _price, uint _amount);
    event FirstOfferAccepted (address _seller, uint _aucId, uint _price, uint _amount);
    event ContractEstablished (uint _aucId, address _buyer, address _seller);
    event ReportOk(uint _aucId);
    event ReportNotOk(uint _aucId);
    event SealedBidReceived(address seller, uint _aucId, bytes32 _sealedBid, uint _bidId);
    event BidNotCorrectelyRevealed(address bidder, uint _price, bytes32 _sealedBid);

    function createReq(uint _amount, uint _price, uint256 _time, uint256 _auctionTime, uint _location) public 
    {
        uint aucId = totalAuction++;
        storeAndLogNewReq(msg.sender, aucId, _amount, _price, _time, _auctionTime, _location);
    } 

    function makeSealedOffer(uint _aucId, bytes32 _sealedBid) public    
        auctionExisit(_aucId)
        auctionNotClosed(_aucId) 
        revealNotEnded(_aucId) 
    {
        auctions[_aucId].bids.push(SealedBid(msg.sender, _sealedBid));
        uint bidId = auctions[_aucId].nbBid;
        auctions[_aucId].nbBid = auctions[_aucId].nbBid++;
        emit SealedBidReceived(msg.sender, _aucId, _sealedBid, bidId);
              
    }

    function closeAuction(uint _aucId) public
        auctionExisit(_aucId) 
        buyerOnly(_aucId)
        //to do: conractNotEstablished(_aucId)
        //auctionTimeOut(_aucId)
    {
        auctions[_aucId].state = AuctionState.Closed;
    }
    
    function endReveal(uint _aucId) public
        auctionExisit(_aucId) 
        buyerOnly(_aucId)
        //to do: conractNotEstablished(_aucId)
        //auctionTimeOut(_aucId)
    {
        auctions[_aucId].state = AuctionState.RevealEnd;
        contracts[_aucId].state= ContractState.Established;
        tokens[contracts[_aucId].buyer].active = true;
    }
    
    function revealOffer (uint _aucId, uint _price, uint _bidId) public 
        auctionExisit(_aucId)
        auctionClosed(_aucId) 
        revealNotEnded(_aucId)
    {        
        if (auctions[_aucId].bids[_bidId].bid != keccak256(abi.encodePacked(_price))) {
        // Bid was not actually revealed.
        emit BidNotCorrectelyRevealed(msg.sender, _price, keccak256(abi.encodePacked(_price)));
        return;
        }
        if (contracts[_aucId].state == ContractState.HasOffer) {
            require(_price < contracts[_aucId].currentPrice);         
            contracts[_aucId].currentPrice = _price;
            contracts[_aucId].seller = msg.sender;
            emit LowestBidDecreased(msg.sender, _aucId, _price, 0);
        } else { // first offer
            require(_price <= contracts[_aucId].buyerMaxPrice);         
            contracts[_aucId].currentPrice = _price; 
            contracts[_aucId].seller = msg.sender;
            contracts[_aucId].state = ContractState.HasOffer;  
            emit FirstOfferAccepted(msg.sender, _aucId, _price, 0); 
        } 
    }

    function setBuyerMeterReport (uint _aucId, bool _state) public 
        auctionExisit(_aucId)
        contractEstablished(_aucId)
    {
        if (!_state) {
            emit ReportNotOk(_aucId);
        }
        contracts[_aucId].buyerMeterReport = _state;
        if (contracts[_aucId].sellerMeterReport) {
            updateBalance(_aucId, contracts[_aucId].buyer, contracts[_aucId].seller);
            emit ReportOk(_aucId);
        }
    }
    // bader code function progress update
    function setBuyerUpdateProgress (uint _aucId, bool _state, uint _amount, uint _locationPad) public
    tokenExisit()
    {
        contracts[_aucId].progress += _amount;
        contracts[_aucId].padsLocation.push(_locationPad);
        if (_state == true || contracts[_aucId].amount <= contracts[_aucId].progress){
           tokens[contracts[_aucId].buyer].active = false;
           setBuyerMeterReport(_aucId,true);
        }
    }
    function setSellerMeterReport (uint _aucId, bool _state) public 
        auctionExisit(_aucId)
        contractEstablished(_aucId)
    {
        if (!_state) {
            emit ReportNotOk(_aucId);
        }
        contracts[_aucId].sellerMeterReport = _state;
        if (contracts[_aucId].buyerMeterReport) {
            updateBalance(_aucId, contracts[_aucId].buyer, contracts[_aucId].seller);
            emit ReportOk(_aucId);
        }
    }

    function updateBalance(uint _aucId, address _buyer, address _seller) public 
        reportsOk(_aucId)   
    {
        uint256 date = contracts[_aucId].deliveryTime;
        uint amount = contracts[_aucId].progress;// bill using progress amount instead of declared
        uint amounToPay = amount * contracts[_aucId].currentPrice;
        accounts[_buyer].payments.push(Payment(_aucId, date, amount, true, amounToPay));
        accounts[_buyer].balance -= int256(amounToPay);
        accounts[_seller].payments.push(Payment(_aucId, date, amount, false, amounToPay));
        accounts[_seller].balance += int256(amounToPay);
        contracts[_aucId].state = ContractState.Closed;
    }

    function registerNewUser(address _user) public {
        //should be added by the utility only
        //later add a modifier: utilityOnly()
        accounts[_user].isUser = true;
    }

    function getReq(uint _index) public view returns(ContractState) {
        return (contracts[_index].state);
    }

    function getNumberOfReq() public view returns (uint) {
        return totalAuction;
    }
    // *Bader Coding Area*
     function getHash(uint _cost) public view returns (bytes32) {
        return keccak256(abi.encodePacked(_cost));
    }
    // request token
    function getToken () public tokenExisit()  view returns (uint[3] memory padLocation, uint _aucId) 
    {
        return (tokens[msg.sender].zoneArea,tokens[msg.sender].aucID);
    }
    // request Report
    function getReport() public reportsOk(tokens[msg.sender].aucID) view returns (address buyer,address seller, uint totalPayment, uint auctionID,uint[] memory padLocation){
        return (contracts[tokens[msg.sender].aucID].buyer,contracts[tokens[msg.sender].aucID].seller,contracts[tokens[msg.sender].aucID].progress, tokens[msg.sender].aucID,contracts[tokens[msg.sender].aucID].padsLocation);
    } 
    ///**
    function storeAndLogNewReq(address _buyer, uint _id, uint _amount, uint _price, uint256 _time, uint256 _auctionTime, uint _location) private {
        contracts[_id].buyer = _buyer;
        contracts[_id].amount = _amount;
        contracts[_id].progress = 0; // added
        contracts[_id].buyerMaxPrice = _price;
        contracts[_id].deliveryTime = _time;
        contracts[_id].auctionTimeOut = now + _auctionTime;
        contracts[_id].deliveryLocation = _location;
        contracts[_id].state = ContractState.Created;
        auctions[_id].state = AuctionState.Created;
        auctions[_id].nbBid = 0;
        
        // token Established but not yet active
        // store in Token arrray of Allowed charged Area
         for (uint i =0; i<3; i++){
             tokens[msg.sender].zoneArea[i]=zone[contracts[tokens[msg.sender].aucID].deliveryLocation-1][i];
        }
        tokens[_buyer].aucID = _id;
        tokens[contracts[_id].buyer].active = false;
        
        emit LogReqCreated(_buyer, _id, _price, _amount, _time, _auctionTime, _location);
    }
    
    /// for testing
    function RUN() public{
        createReq(50,10,1,1,3);
        makeSealedOffer(0,0x036b6384b5eca791c62761152d0c79bb0604c104a5fb6f4eb0703f3154bb3db0);
        closeAuction(0);
        revealOffer(0,5,0);
        endReveal(0);
    }

}
